import Foundation

/// Builds the ~/.claude/settings.json Mely needs, without touching the disk: the app
/// shows `LineDiff` of the result, and writes it with `ClaudeSettingsFile.write` only
/// after the user confirms.
public enum ClaudeHookInstaller {
    /// Events relayed to Mely and their hook timeouts (seconds). PermissionRequest waits
    /// for a click, so its timeout is just above the relay's 118 s.
    public static let events: [(name: String, timeout: Int)] = [
        ("SessionStart", 10), ("SessionEnd", 10), ("UserPromptSubmit", 10),
        ("PreToolUse", 10), ("PostToolUse", 10), ("PostToolUseFailure", 10),
        ("PermissionRequest", 120), ("Notification", 10),
        ("Stop", 10), ("StopFailure", 10), ("SubagentStart", 10), ("SubagentStop", 10),
    ]
    /// AskUserQuestion arrives as PreToolUse (Claude Code 2.1.85+): its own hook waits for the answer.
    public static let askTimeout = 130

    /// The hook command, quoted.
    public static func command(relayPath: String) -> String {
        "\"\(relayPath.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    /// Settings with Mely's hooks added (or refreshed). Other tools' hooks stay as they are.
    public static func installing(into settings: [String: Any], relayPath: String) throws -> [String: Any] {
        var settings = settings
        var hooks = try ClaudeSettingsFile.hooks(in: settings, name: "settings.json")
        let cmd = command(relayPath: relayPath)
        for (event, timeout) in events {
            var groups = try ClaudeSettingsFile.hookGroups(in: hooks, event: event, name: "settings.json")
            groups = strip(groups, relayPath: relayPath)
            groups.append(["hooks": [["type": "command", "command": cmd, "timeout": timeout]]])
            hooks[event] = groups
        }
        var pre = hooks["PreToolUse"] as? [[String: Any]] ?? []
        pre.append(["matcher": "AskUserQuestion",
                    "hooks": [["type": "command", "command": "\(cmd) --ask", "timeout": askTimeout]]])
        hooks["PreToolUse"] = pre
        settings["hooks"] = hooks
        return settings
    }

    /// Settings without Mely's hooks. Events left with no hook are removed; nothing else changes.
    public static func uninstalling(from settings: [String: Any], relayPath: String? = nil) throws -> [String: Any] {
        var settings = settings
        guard settings["hooks"] != nil else { return settings }
        var hooks = try ClaudeSettingsFile.hooks(in: settings, name: "settings.json")
        for key in hooks.keys {
            guard let groups = hooks[key] as? [[String: Any]] else { continue }
            let kept = strip(groups, relayPath: relayPath)
            hooks[key] = kept.isEmpty ? nil : kept
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    // MARK: statusLine

    /// What the statusLine wrapper calls after relaying the limits: the command the user
    /// had before (`nc-hook --statusline` reads it from `statusline-previous.json`).
    public enum PreviousStatusLine: Equatable, Sendable {
        /// Leave the saved file as it is (Mely's wrapper was already there).
        case keep
        /// Save this statusLine object as JSON; nil deletes the file (nothing to call).
        case save(Data?)
    }

    public static func statusLineCommand(relayPath: String) -> String {
        command(relayPath: relayPath) + " --statusline"
    }

    /// Settings with Mely's statusLine wrapper. The statusLine it replaces is returned to
    /// be saved, so its output keeps showing in Claude Code.
    public static func installingStatusLine(into settings: [String: Any], relayPath: String)
        -> (settings: [String: Any], previous: PreviousStatusLine) {
        let current = settings["statusLine"] as? [String: Any]
        let currentCommand = current?["command"] as? String ?? ""
        if HookDetection.isMelyCommand(currentCommand, relayPath: relayPath) { return (settings, .keep) }
        let previous = current
        var line: [String: Any] = ["type": "command", "command": statusLineCommand(relayPath: relayPath)]
        if let padding = current?["padding"] { line["padding"] = padding }
        var settings = settings
        settings["statusLine"] = line
        let data = previous.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
        return (settings, .save(data))
    }

    /// Settings with the user's statusLine back in place of Mely's wrapper (or none).
    public static func uninstallingStatusLine(from settings: [String: Any], relayPath: String?,
                                              previous: [String: Any]?) -> [String: Any] {
        guard let command = (settings["statusLine"] as? [String: Any])?["command"] as? String,
              HookDetection.isMelyCommand(command, relayPath: relayPath) else { return settings }
        var settings = settings
        settings["statusLine"] = previous
        return settings
    }

    public static func statusLineInstalled(in settings: [String: Any], relayPath: String? = nil) -> Bool {
        guard let command = (settings["statusLine"] as? [String: Any])?["command"] as? String else { return false }
        return HookDetection.isMelyCommand(command, relayPath: relayPath)
    }

    /// Drops Mely's commands from hook groups; empty groups go.
    static func strip(_ groups: [[String: Any]], relayPath: String?) -> [[String: Any]] {
        groups.compactMap { group in
            guard let inner = group["hooks"] as? [[String: Any]] else { return group }
            let kept = inner.filter { hook in
                guard let c = hook["command"] as? String else { return true }
                return !HookDetection.isMelyCommand(c, relayPath: relayPath)
            }
            if kept.isEmpty { return nil }
            var g = group
            g["hooks"] = kept
            return g
        }
    }

    /// Pretty, stable JSON for writing and for the diff.
    public static func encode(_ settings: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

/// A line diff (longest common subsequence) for showing a settings change.
public enum LineDiff {
    public enum Line: Equatable, Sendable {
        case same(String), added(String), removed(String)
    }

    public static func lines(from old: String, to new: String) -> [Line] {
        let a = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [Line] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                out.append(.same(a[i])); i += 1; j += 1
            } else if i < a.count, j == b.count || lcs[i + 1][j] >= lcs[i][j + 1] {
                // Removals before additions, as diff tools show them.
                out.append(.removed(a[i])); i += 1
            } else {
                out.append(.added(b[j])); j += 1
            }
        }
        return out
    }

    /// Only the changed lines and `context` lines around them, `@@` between hunks.
    public static func text(from old: String, to new: String, context: Int = 2) -> String {
        let all = lines(from: old, to: new)
        let changed = all.indices.filter { if case .same = all[$0] { return false } else { return true } }
        guard !changed.isEmpty else { return "" }
        var keep = Set<Int>()
        for c in changed { for k in max(0, c - context)...min(all.count - 1, c + context) { keep.insert(k) } }
        var out: [String] = []
        var last = -2
        for idx in keep.sorted() {
            if idx != last + 1 && !out.isEmpty { out.append("@@") }
            switch all[idx] {
            case .same(let s): out.append("  " + s)
            case .added(let s): out.append("+ " + s)
            case .removed(let s): out.append("- " + s)
            }
            last = idx
        }
        return out.joined(separator: "\n")
    }
}
