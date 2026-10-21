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

    private var recheck: Timer?

    /// `ended` gets the session id.
    init(ended: @escaping (String) -> Void) {
        self.ended = ended
    }

    /// The exit event does not come for a process left half-exited (a tab closed in
    /// WebStorm): every few seconds, look at each watched process too.
    private func startRechecking() {
        guard recheck == nil else { return }
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for (id, entry) in self.watched where !entry.process.isAlive() { self.exited(id, entry.process) }
                if self.watched.isEmpty { self.recheck?.invalidate(); self.recheck = nil }
            }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        recheck = t
    }

    /// Follows the session's process; a new process (a resumed session) replaces the old one.
    func watch(_ sessionId: String, process: ProcessIdentity) {
        guard watched[sessionId]?.process != process else { return }
        forget(sessionId)
        log.info("session=\(sessionId.prefix(8), privacy: .public) watching process \(process.pid)")
        let source = DispatchSource.makeProcessSource(identifier: process.pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.exited(sessionId, process) }
        }
        watched[sessionId] = (process, source)
        source.resume()
        startRechecking()
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
