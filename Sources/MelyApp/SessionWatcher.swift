import Foundation
import OSLog
import MelyCore

private let log = Logger(subsystem: "dev.mely.app", category: "hooks")

/// Ends a session when its Claude Code process exits: a closed terminal window or a
/// killed process sends no SessionEnd.
@MainActor
final class SessionWatcher {
    private let ended: (String) -> Void
    private var watched: [String: (process: ProcessIdentity, source: DispatchSourceProcess)] = [:]

    /// `ended` gets the session id.
    init(ended: @escaping (String) -> Void) {
        self.ended = ended
    }

    /// Follows the session's process; a new process (a resumed session) replaces the old one.
    func watch(_ sessionId: String, process: ProcessIdentity) {
        guard watched[sessionId]?.process != process else { return }
        forget(sessionId)
        let source = DispatchSource.makeProcessSource(identifier: process.pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.exited(sessionId, process) }
        }
        watched[sessionId] = (process, source)
        source.resume()
        // It may be gone already (or the pid is someone else's now): the source never fires
        // then. Not right here: the event that brought the process is still being handled.
        if !process.isAlive() { Task { @MainActor [weak self] in self?.exited(sessionId, process) } }
    }

    func forget(_ sessionId: String) {
        watched.removeValue(forKey: sessionId)?.source.cancel()
    }

    private func exited(_ sessionId: String, _ process: ProcessIdentity) {
        guard watched[sessionId]?.process == process else { return }
        forget(sessionId)
        log.info("session=\(sessionId.prefix(8), privacy: .public) process \(process.pid) exited")
        ended(sessionId)
    }
}
