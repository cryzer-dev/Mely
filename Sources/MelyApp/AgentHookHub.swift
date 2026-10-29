import Foundation
import OSLog
import MelyCore

private let hubLog = Logger(subsystem: "dev.mely.app", category: "hooks")

/// The hook socket shared by the agents: open while any agent is on. Events of an agent
/// that is off (its hooks left behind) get «ask in the terminal» and go no further.
@MainActor
final class AgentHookHub {
    /// Receives decoded events of the agents that are on.
    var onEvent: ((HookEvent, HookOrigin, HookResponder?) -> Void)?
    private var server: HookSocketServer?
    private var agents: Set<Agent> = []

    /// An agent switched on: the socket opens with the first.
    func open(for agent: Agent) throws {
        agents.insert(agent)
        guard server == nil else { return }
        let server = HookSocketServer(path: AppInfo.socketURL.path) { [weak self] payload, responder in
            let box = JSONObject(payload)
            Task { @MainActor in self?.receive(box.value, responder) }
        }
        do {
            try server.start()
            self.server = server
        } catch {
            agents.remove(agent)
            throw error
        }
    }

    /// An agent switched off: the socket closes with the last.
    func close(for agent: Agent) {
        agents.remove(agent)
        guard agents.isEmpty else { return }
        server?.stop()
        server = nil
    }

    private func receive(_ payload: [String: Any], _ responder: HookResponder?) {
        let (event, origin) = HookEvent.decode(payload)
        guard agents.contains(origin.agent), let onEvent else {
            hubLog.info("event of \(origin.agent.rawValue, privacy: .public) while it is off")
            responder?.reply(.ask)
            return
        }
        onEvent(event, origin, responder)
    }
}
