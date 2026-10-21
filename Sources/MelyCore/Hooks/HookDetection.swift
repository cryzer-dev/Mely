import Foundation

/// Recognizes hook commands in a parsed ~/.claude/settings.json. Kept free of file
/// access so it can be tested on fixtures.
public enum HookDetection {
    /// Mely's hook command runs `~/.mely/bin/nc-hook` (or `relayPath` when given).
    public static func isMelyCommand(_ command: String, relayPath: String? = nil) -> Bool {
        if let relayPath, command.contains(relayPath) { return true }
        return command.contains("/.mely/bin/nc-hook")
    }

    /// True when SessionStart events reach Mely.
    public static func melyHooksPresent(inSettings settings: [String: Any], relayPath: String? = nil) -> Bool {
        sessionStartCommands(settings).contains { isMelyCommand($0, relayPath: relayPath) }
    }

    private static func sessionStartCommands(_ settings: [String: Any]) -> [String] {
        guard let hooks = settings["hooks"] as? [String: Any],
              let groups = hooks["SessionStart"] as? [[String: Any]] else { return [] }
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.compactMap { $0["command"] as? String }
    }
}
