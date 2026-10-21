import Foundation
import Observation

/// `AskUserQuestion` input: 1–4 questions, single or multiple choice.
public struct QuestionPayload: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public let label: String
        public let description: String?
    }

    public struct Question: Equatable, Sendable {
        /// Full question text; Claude Code keys the answers by it.
        public let text: String
        /// Short chip ("Библиотека").
        public let header: String?
        public let options: [Option]
        public let multiSelect: Bool
    }

    public let questions: [Question]

    /// Nil when the input holds no usable question.
    public init?(_ input: [String: Any]) {
        let raw = input["questions"] as? [[String: Any]] ?? []
        let questions = raw.compactMap { q -> Question? in
            guard let text = q["question"] as? String, !text.isEmpty else { return nil }
            let options = (q["options"] as? [[String: Any]] ?? []).compactMap { o -> Option? in
                guard let label = o["label"] as? String, !label.isEmpty else { return nil }
                return Option(label: label, description: (o["description"] as? String).flatMap { $0.isEmpty ? nil : $0 })
            }
            return Question(text: text, header: (q["header"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                            options: options, multiSelect: q["multiSelect"] as? Bool ?? false)
        }
        guard !questions.isEmpty else { return nil }
        self.questions = questions
    }

    /// One single-choice question: a click on an option is the whole answer.
    public var answersWithOneClick: Bool { questions.count == 1 && !questions[0].multiSelect }
}

/// A permission request or a question waiting for the user.
public struct PendingRequest: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// `detail`: the command or file, shown in full.
        case approval(tool: String, title: String, detail: String?, canAlways: Bool)
        case question(QuestionPayload)
    }

    public let id: Int
    public let sessionId: String
    public let projectName: String
    public let hostName: String
    public let kind: Kind
    public let createdAt: Date

    public var isQuestion: Bool {
        if case .question = kind { return true }
        return false
    }

    var tool: String {
        switch kind {
        case .approval(let tool, _, _, _): tool
        case .question: "AskUserQuestion"
        }
    }
}

/// Blocking requests from every session, answered in the order they came.
/// Nothing is ever allowed without `resolve` (a click).
@MainActor
@Observable
public final class ApprovalQueue {
    public private(set) var requests: [PendingRequest] = []
    @ObservationIgnored private var responders: [Int: HookResponder] = [:]
    @ObservationIgnored private var nextId = 1

    public init() {}

    public var current: PendingRequest? { requests.first }

    public func hasPending(session id: String) -> Bool { requests.contains { $0.sessionId == id } }

    /// Queues a blocking event. Nil for events that don't wait for the user.
    @discardableResult
    public func enqueue(_ event: HookEvent, session: ClaudeSession, responder: HookResponder,
                        now: Date = Date()) -> PendingRequest? {
        let kind: PendingRequest.Kind
        switch event {
        case .permissionRequest(let tool, let input, let suggestions):
            let items = suggestions["items"] as? [Any] ?? []
            kind = .approval(tool: tool, title: StepLabel.label(tool: tool, input: input.value),
                             detail: Self.detail(tool: tool, input: input.value), canAlways: !items.isEmpty)
        case .question(let input):
            guard let payload = QuestionPayload(input.value) else { return nil }
            kind = .question(payload)
        default:
            return nil
        }
        // The same question can come twice (PreToolUse --ask, then PermissionRequest): keep one card.
        if case .question = kind, let old = requests.first(where: { $0.sessionId == session.id && $0.kind == kind }) {
            responders[old.id]?.reply(.ask)
            responders[old.id] = responder
            return old
        }
        let request = PendingRequest(id: nextId, sessionId: session.id, projectName: session.projectName,
                                     hostName: session.host.name, kind: kind, createdAt: now)
        nextId += 1
        requests.append(request)
        responders[request.id] = responder
        return request
    }

    /// Sends the user's decision and drops the card.
    public func resolve(_ id: Int, with decision: HookDecision) {
        responders.removeValue(forKey: id)?.reply(decision)
        requests.removeAll { $0.id == id }
    }

    /// A later event of the session shows the request was settled elsewhere (in the
    /// terminal, or Claude Code gave up waiting). Returns the dropped requests.
    @discardableResult
    public func settle(after event: HookEvent, session id: String) -> [PendingRequest] {
        let stale: (PendingRequest) -> Bool
        switch event {
        case .toolFinished(let tool, _, _):
            stale = { $0.tool == tool }
        case .userPrompt, .stop, .stopFailure, .sessionEnd:
            stale = { _ in true }
        default:
            return []
        }
        return drop { $0.sessionId == id && stale($0) }
    }

    /// Drops requests whose `nc-hook` already hung up (timeout or the user answered in
    /// the terminal and Claude Code stopped the hook).
    @discardableResult
    public func sweep() -> [PendingRequest] {
        drop { [responders] in responders[$0.id]?.isPeerConnected != true }
    }

    private func drop(_ predicate: (PendingRequest) -> Bool) -> [PendingRequest] {
        let gone = requests.filter(predicate)
        for r in gone { responders.removeValue(forKey: r.id)?.reply(.ask) }
        requests.removeAll(where: predicate)
        return gone
    }

    /// What exactly would run: the full command, or the file.
    static func detail(tool: String, input: [String: Any]) -> String? {
        if let command = input["command"] as? String { return command }
        if let path = input["file_path"] as? String ?? input["notebook_path"] as? String { return path }
        if let url = input["url"] as? String { return url }
        if let pattern = input["pattern"] as? String { return pattern }
        return nil
    }
}
