import Foundation
import Observation

/// What a Claude Code session is doing.
public enum SessionState: Equatable, Sendable {
    case idle
    case thinking
    case working
    case waitingApproval
    case waitingAnswer
    case finished(summary: String)
    case error(String)
    case rateLimited
}

public struct ClaudeSession: Identifiable, Equatable, Sendable {
    public let id: String
    public var origin: HookOrigin
    public var host: SessionHost
    public var state: SessionState = .idle
    /// Current ticker line ("Правит · Cart.tsx").
    public var step: String?
    /// Files changed in the current turn, newest last.
    public var diffs: [FileDiff] = []
    public var subagents = 0
    public var lastSeen: Date
    public let startedAt: Date

    public var projectName: String { origin.projectName }
    public var addedLines: Int { diffs.reduce(0) { $0 + $1.added } }
    public var removedLines: Int { diffs.reduce(0) { $0 + $1.removed } }
    public var lastDiff: FileDiff? { diffs.last }
}

/// Live Claude Code sessions, one entry per session id, so two projects in the same
/// WebStorm both show up. Fed with hook events on the main actor.
@MainActor
@Observable
public final class SessionStore {
    /// Sessions in the order they started.
    public private(set) var sessions: [ClaudeSession] = []

    /// A session silent this long is gone (its SessionEnd never came: killed terminal, crash).
    public static let maxSilence: TimeInterval = 12 * 3600
    /// A turn silent this long lost its Stop: the session stops counting as working.
    public static let maxTurnSilence: TimeInterval = 30 * 60

    @ObservationIgnored private var nextDiffId = 1

    public init() {}

    public func session(_ id: String) -> ClaudeSession? { sessions.first { $0.id == id } }

    public var workingCount: Int {
        sessions.filter { [.thinking, .working].contains($0.state) }.count
    }

    /// Applies one hook event. Returns the updated session (nil when it ended or the
    /// event is not about a session).
    @discardableResult
    public func apply(_ event: HookEvent, origin: HookOrigin, now: Date = Date()) -> ClaudeSession? {
        sweep(now: now)
        if case .statusLine = event { return nil }
        if case .sessionEnd = event {
            sessions.removeAll { $0.id == origin.sessionId }
            return nil
        }
        var s = session(origin.sessionId)
            ?? ClaudeSession(id: origin.sessionId, origin: origin, host: SessionHost.resolve(origin),
                             lastSeen: now, startedAt: now)
        // Later events may carry fuller context (cwd, host) than the first one.
        if !origin.cwd.isEmpty { s.origin.cwd = origin.cwd }
        if !origin.hostBundleId.isEmpty || !origin.termProgram.isEmpty || !origin.terminalEmulator.isEmpty {
            s.origin = origin
            s.host = SessionHost.resolve(origin)
        }
        s.lastSeen = now

        switch event {
        case .sessionStart:
            s.state = .idle
        case .userPrompt(let prompt):
            s.state = .thinking
            s.step = prompt.isEmpty ? nil : StepLabel.oneLine(prompt)
            s.diffs = []
        case .toolStarted(let tool, let input):
            guard tool != "AskUserQuestion" else { break }
            s.state = .working
            s.step = StepLabel.label(tool: tool, input: input.value)
        case .toolFinished(let tool, let input, let failed):
            if !failed, var diff = StepLabel.diff(tool: tool, input: input.value) {
                diff.id = nextDiffId
                nextDiffId += 1
                s.diffs.append(diff)
            }
            if s.state != .waitingApproval && s.state != .waitingAnswer { s.state = .working }
        case .permissionRequest(let tool, let input, _):
            s.state = .waitingApproval
            s.step = StepLabel.label(tool: tool, input: input.value)
        case .question:
            s.state = .waitingAnswer
        case .notification(let type, let message):
            if Self.isRateLimit(message) {
                s.state = .rateLimited
            } else if type == "idle_prompt" {
                s.state = .idle
            }
        case .stop(let lastMessage):
            s.state = .finished(summary: lastMessage.map { DiffEngine.toOneLine($0, maxChars: 140) } ?? "")
            s.subagents = 0
        case .stopFailure(let message):
            s.state = Self.isRateLimit(message ?? "") ? .rateLimited : .error(message ?? "Ошибка")
        case .subagentStarted:
            s.subagents += 1
        case .subagentStopped:
            s.subagents = max(0, s.subagents - 1)
        case .statusLine, .sessionEnd, .unknown:
            break
        }

        if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s } else { sessions.append(s) }
        return s
    }

    /// The user answered (approval or question) in the notch or the terminal: back to work.
    public func resumeWork(_ id: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        if sessions[i].state == .waitingApproval || sessions[i].state == .waitingAnswer {
            sessions[i].state = .working
        }
    }

    /// The finished state shows for a moment, then the session rests.
    public func settle(_ id: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }),
              case .finished = sessions[i].state else { return }
        sessions[i].state = .idle
    }

    public func sweep(now: Date = Date()) {
        sessions.removeAll { now.timeIntervalSince($0.lastSeen) > Self.maxSilence }
        for i in sessions.indices where [.thinking, .working].contains(sessions[i].state)
            && now.timeIntervalSince(sessions[i].lastSeen) > Self.maxTurnSilence {
            sessions[i].state = .idle
        }
    }

    /// State name without content, safe for logs.
    public static func stateName(_ state: SessionState) -> String {
        switch state {
        case .idle: "idle"
        case .thinking: "thinking"
        case .working: "working"
        case .waitingApproval: "waitingApproval"
        case .waitingAnswer: "waitingAnswer"
        case .finished: "finished"
        case .error: "error"
        case .rateLimited: "rateLimited"
        }
    }

    static func isRateLimit(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("rate_limit") || t.contains("usage limit") || t.contains("limit reached")
            || t.contains("rate limit")
    }
}
