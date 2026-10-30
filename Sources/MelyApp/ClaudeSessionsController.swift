import Foundation
import OSLog
import MelyCore
import MelyUI

private let log = Logger(subsystem: "dev.mely.app", category: "hooks")

/// Turns Claude Code hook events into session state and island activity.
@MainActor
final class ClaudeSessionsController {
    let store = SessionStore()
    let queue = ApprovalQueue()
    let usage = PlanUsageStore()
    private let island: IslandModel
    private let reveal: () -> Void
    private let expand: () -> Void
    private let peek: (PeekContent) -> Void
    /// An agent's request came or its turn ended (the island may open for it).
    var agentEvent: ((Agent) -> Void)?
    private var settleTasks: [String: Task<Void, Never>] = [:]
    private var sweepTimer: Timer?
    private lazy var watcher = SessionWatcher { [weak self] id in self?.processEnded(id) }

    /// How long "Готово" stays before the session rests.
    static let finishedHold: Duration = .milliseconds(5200)

    init(island: IslandModel, reveal: @escaping () -> Void, expand: @escaping () -> Void,
         peek: @escaping (PeekContent) -> Void) {
        self.island = island
        self.reveal = reveal
        self.expand = expand
        self.peek = peek
    }

    func handle(_ event: HookEvent, origin: HookOrigin, responder: HookResponder?) {
        if case .statusLine(let limits) = event {
            let wasWarning = usage.usage?.current().isWarning == true
            usage.update(rateLimits: limits.value)
            // Crossing 80% is worth a look.
            if !wasWarning, usage.usage?.current().isWarning == true { reveal() }
            return
        }
        // A later event of the session means its request was settled in the terminal.
        let settled = queue.settle(after: event, session: origin.sessionId)
        forget(settled)
        let before = store.session(origin.sessionId)?.state
        let session = store.apply(event, origin: origin)
        if let responder {
            if let session, let request = queue.enqueue(event, session: session, responder: responder) {
                agentEvent?(session.agent)
                island.post(IslandItem(id: Self.itemId(request), kind: request.isQuestion ? .question : .approval,
                                       source: session.agent.integrationId, title: request.projectName))
                startSweeping()
                SoundEngine.shared.play(request.isQuestion ? .question : .approval)
                expand()
            } else {
                responder.reply(.ask)
            }
        }
        log.info("event \(event.name, privacy: .public) session=\(origin.sessionId.prefix(8), privacy: .public) host=\(origin.hostBundleId, privacy: .public) state=\(session.map { SessionStore.stateName($0.state) } ?? "-", privacy: .public)")
        guard let session else {
            watcher.forget(origin.sessionId)
            island.remove(id: "session-\(origin.sessionId)")
            return
        }
        if let process = session.origin.process {
            watcher.watch(session.id, process: process)
        } else {
            log.info("session=\(session.id.prefix(8), privacy: .public) has no process")
        }
        let itemId = "session-\(session.id)"
        switch session.state {
        case .thinking, .working:
            island.post(IslandItem(id: itemId, kind: .agentActivity, source: session.agent.integrationId,
                                   title: session.projectName, subtitle: session.step))
            // A new turn shows for a moment; its every tool step does not.
            if IslandWings.startsTurn(from: before, to: session.state) { reveal() }
        case .finished(let summary):
            island.remove(id: itemId)
            if before != session.state {
                SoundEngine.shared.play(.finish)
                agentEvent?(session.agent)
            }
            peek(PeekContent(id: itemId, symbol: "checkmark", tint: .green,
                             title: "Готово · \(session.projectName)",
                             subtitle: summary.isEmpty ? session.host.name : summary,
                             appBundleId: session.host.bundleId))
            settleTasks[session.id]?.cancel()
            settleTasks[session.id] = Task { [weak self] in
                try? await Task.sleep(for: Self.finishedHold)
                guard !Task.isCancelled else { return }
                self?.store.settle(session.id)
            }
        case .error(let message):
            island.remove(id: itemId)
            if before != session.state { SoundEngine.shared.play(.error) }
            peek(PeekContent(id: itemId, symbol: "exclamationmark.triangle.fill", tint: .red,
                             title: "Ошибка · \(session.projectName)", subtitle: message))
        case .rateLimited:
            island.remove(id: itemId)
            if before != session.state { SoundEngine.shared.play(.limit) }
            peek(PeekContent(id: itemId, symbol: "hourglass", tint: .yellow,
                             title: "Лимит \(session.agent.shortName) · \(session.projectName)", subtitle: "Сессия упёрлась в лимит плана"))
        default:
            island.remove(id: itemId)
        }
    }

    /// The session's process exited without SessionEnd: end it the same way.
    private func processEnded(_ id: String) {
        guard let session = store.session(id) else { return }
        handle(.sessionEnd, origin: session.origin, responder: nil)
    }

    /// The user clicked a button on the card.
    func decide(_ request: PendingRequest, _ decision: HookDecision) {
        log.info("decision for request \(request.id)")
        queue.resolve(request.id, with: decision)
        forget([request])
    }

    /// "В терминале": Claude Code asks there, and the host comes forward.
    func answerInTerminal(_ request: PendingRequest) {
        queue.resolve(request.id, with: .ask)
        island.remove(id: Self.itemId(request))
        if let session = store.session(request.sessionId) {
            HostActivator.activate(session.host, origin: session.origin)
        }
    }

    private static func itemId(_ request: PendingRequest) -> String { "request-\(request.id)" }

    /// Cards gone: unhold the island, and the session works again once nothing waits.
    private func forget(_ requests: [PendingRequest]) {
        for request in requests {
            island.remove(id: Self.itemId(request))
            if !queue.hasPending(session: request.sessionId) { store.resumeWork(request.sessionId) }
        }
    }

    /// `nc-hook` hangs up when Claude Code stops waiting: drop its card within a couple of seconds.
    private func startSweeping() {
        guard sweepTimer == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for request in self.queue.sweep() { self.island.remove(id: Self.itemId(request)) }
                if self.queue.requests.isEmpty {
                    self.sweepTimer?.invalidate()
                    self.sweepTimer = nil
                }
            }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        sweepTimer = t
    }
}
