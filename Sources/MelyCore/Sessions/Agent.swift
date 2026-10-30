import Foundation

/// A coding agent whose sessions the notch shows. Claude Code is the first: with several
/// on, it comes first in the switcher and its limits are in the notch by default.
public enum Agent: String, CaseIterable, Codable, Sendable {
    case claude, codex

    /// «Claude Code», «Codex»: the switcher, the settings.
    public var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// «Claude спрашивает», «Лимит Codex».
    public var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// Its integration in the registry: on there, it is on in the notch.
    public var integrationId: String {
        switch self {
        case .claude: "claude-code"
        case .codex: "codex"
        }
    }

    public init?(integrationId: String) {
        guard let agent = Agent.allCases.first(where: { $0.integrationId == integrationId }) else { return nil }
        self = agent
    }

    /// What `nc-hook --agent <name>` puts in `HookWire.agentKey`; none means Claude Code
    /// (its hooks were installed before there was a choice).
    public init(wire: String?) {
        self = wire.flatMap(Agent.init(rawValue:)) ?? .claude
    }

    /// The store's id of a session: Claude's as Claude Code reports it (ids saved by older
    /// versions stay valid), another agent's prefixed so two agents never share one.
    public func sessionKey(_ sessionId: String) -> String {
        self == .claude ? sessionId : "\(rawValue):\(sessionId)"
    }
}
