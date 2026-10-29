import Foundation

/// Builds `~/.codex/hooks.json` with Mely's hooks, without touching the disk, as
/// `ClaudeHookInstaller` does for Claude Code. Codex runs a hook only once it is trusted:
/// `CodexHookTrust` writes that approval into `config.toml`.
public enum CodexHookInstaller {
    /// Events relayed to Mely and their timeouts (seconds; Codex's default is 600).
    /// PermissionRequest waits for a click, just above the relay's 118 s.
    public static let events: [(name: String, timeout: Int)] = [
        ("SessionStart", 10), ("SessionEnd", 10), ("UserPromptSubmit", 10),
        ("PreToolUse", 10), ("PostToolUse", 10), ("PermissionRequest", 120),
        ("Stop", 10), ("SubagentStart", 10), ("SubagentStop", 10), ("Interrupt", 10),
    ]
    /// Shown by Codex while it waits for the answer in the notch.
    public static let waitingMessage = "Ждёт ответа в Mely"

    public static func command(relayPath: String) -> String {
        ClaudeHookInstaller.command(relayPath: relayPath) + " --agent codex"
    }

    /// A Mely hook of Codex (the relay with `--agent codex`).
    public static func isMelyCommand(_ command: String, relayPath: String?) -> Bool {
        HookDetection.isMelyCommand(command, relayPath: relayPath) && command.contains("--agent codex")
    }

    /// hooks.json with Mely's hooks added (or refreshed). Other hooks stay as they are.
    public static func installing(into file: [String: Any], relayPath: String) throws -> [String: Any] {
        var file = file
        var hooks = try ClaudeSettingsFile.hooks(in: file, name: "hooks.json")
        let cmd = command(relayPath: relayPath)
        for (event, timeout) in events {
            var groups = strip(try ClaudeSettingsFile.hookGroups(in: hooks, event: event, name: "hooks.json"), relayPath: relayPath)
            var hook: [String: Any] = ["type": "command", "command": cmd, "timeout": timeout]
            if event == "PermissionRequest" { hook["statusMessage"] = waitingMessage }
            groups.append(["hooks": [hook]])
            hooks[event] = groups
        }
        file["hooks"] = hooks
        return file
    }

    /// hooks.json without Mely's hooks; events left with none are removed.
    public static func uninstalling(from file: [String: Any], relayPath: String?) throws -> [String: Any] {
        var file = file
        guard file["hooks"] != nil else { return file }
        var hooks = try ClaudeSettingsFile.hooks(in: file, name: "hooks.json")
        for key in hooks.keys {
            guard let groups = hooks[key] as? [[String: Any]] else { continue }
            let kept = strip(groups, relayPath: relayPath)
            hooks[key] = kept.isEmpty ? nil : kept
        }
        file["hooks"] = hooks.isEmpty ? nil : hooks
        return file
    }

    /// Where a Mely hook sits in the file: what Codex's trust key is made of.
    public struct Slot: Hashable, Sendable {
        public let event: String
        public let group: Int
        public let handler: Int

        /// `<hooks.json path>:<event in snake_case>:<group>:<handler>`, as `hooks/list` reports it.
        public func key(hooksPath: String) -> String { "\(hooksPath):\(suffix)" }
        public var suffix: String { "\(CodexHookInstaller.snakeCase(event)):\(group):\(handler)" }
    }

    public static func melySlots(in file: [String: Any], relayPath: String?) -> [Slot] {
        let hooks = file["hooks"] as? [String: Any] ?? [:]
        return hooks.keys.sorted().flatMap { event -> [Slot] in
            let groups = hooks[event] as? [[String: Any]] ?? []
            return groups.enumerated().flatMap { g, group -> [Slot] in
                ((group["hooks"] as? [[String: Any]]) ?? []).enumerated().compactMap { h, hook in
                    guard let c = hook["command"] as? String, isMelyCommand(c, relayPath: relayPath) else { return nil }
                    return Slot(event: event, group: g, handler: h)
                }
            }
        }
    }

    /// "PermissionRequest" → "permission_request".
    static func snakeCase(_ event: String) -> String {
        var out = ""
        for (i, c) in event.enumerated() {
            if c.isUppercase, i > 0 { out += "_" }
            out += c.lowercased()
        }
        return out
    }

    /// Whether every relayed event has Mely's hook.
    public static func complete(_ file: [String: Any], relayPath: String?) -> Bool {
        Set(melySlots(in: file, relayPath: relayPath).map(\.event)).isSuperset(of: events.map(\.name))
    }

    static func strip(_ groups: [[String: Any]], relayPath: String?) -> [[String: Any]] {
        groups.compactMap { group in
            guard let inner = group["hooks"] as? [[String: Any]] else { return group }
            let kept = inner.filter { hook in
                guard let c = hook["command"] as? String else { return true }
                return !isMelyCommand(c, relayPath: relayPath)
            }
            if kept.isEmpty { return nil }
            var g = group
            g["hooks"] = kept
            return g
        }
    }
}

/// Codex's approval of hooks in `config.toml`: `[hooks.state."<key>"] trusted_hash = "sha256:…"`.
/// Mely edits only its own tables, as text: the rest of the file (comments, order) stays
/// byte for byte. Each of Mely's tables follows a marker comment, so it can be found again.
public enum CodexHookTrust {
    static let marker = "# Mely: одобрение hooks Mely для Codex (уберётся вместе с ними)"

    /// The config with these approvals: any table for the same keys (an older hash, one
    /// Codex wrote itself) and Mely's earlier tables are replaced.
    public static func trusting(_ config: String, hashes: [String: String]) -> String {
        var text = untrusting(config, keys: Set(hashes.keys))
        guard !hashes.isEmpty else { return text }
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        if !text.isEmpty { text += "\n" }
        text += hashes.keys.sorted().map { key in
            "\(marker)\n[hooks.state.\(quoted(key))]\ntrusted_hash = \(quoted(hashes[key]!))\n"
        }.joined(separator: "\n")
        return text
    }

    /// The config without Mely's approvals and without any table for these keys.
    public static func untrusting(_ config: String, keys: Set<String> = []) -> String {
        let headers = Set(keys.map { "[hooks.state.\(quoted($0))]" })
        var out: [Substring] = []
        // Inside a table to drop; the marker drops the table right under it.
        var skipping = false, marked = false
        for line in config.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == marker {
                marked = true
                continue
            }
            if trimmed.hasPrefix("[") {
                skipping = marked || headers.contains(trimmed)
                marked = false
            }
            // A comment the user put there stays; the table's keys go.
            if !skipping || trimmed.hasPrefix("#") { out.append(line) }
        }
        // No blank lines piling up where tables were.
        var text = out.joined(separator: "\n")
        while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        while text.hasSuffix("\n") { text.removeLast() }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        // A text file ends with a newline (Codex's config does).
        return text + "\n"
    }

    /// `trusted_hash` of each `[hooks.state."…"]` table in the config.
    public static func trustedHashes(in config: String) -> [String: String] {
        var result: [String: String] = [:]
        var current: String?
        for line in config.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") {
                current = nil
                if t.hasPrefix("[hooks.state.\""), t.hasSuffix("\"]") {
                    current = unquoted(String(t.dropFirst("[hooks.state.".count).dropLast()))
                }
            } else if let key = current, t.hasPrefix("trusted_hash"), let eq = t.firstIndex(of: "=") {
                result[key] = unquoted(t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces))
            }
        }
        return result
    }

    /// The hashes Codex computed for Mely's hooks (`hooks/list` over a copy of the future
    /// hooks.json), keyed by the slot's suffix: the hash does not depend on the file's path.
    public static func hashes(fromHooksList response: [String: Any], relayPath: String?) -> [String: String] {
        let entries = (response["data"] as? [[String: Any]] ?? []).flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
        var result: [String: String] = [:]
        for hook in entries {
            guard let command = hook["command"] as? String, CodexHookInstaller.isMelyCommand(command, relayPath: relayPath),
                  let key = hook["key"] as? String, let hash = hook["currentHash"] as? String,
                  let path = hook["sourcePath"] as? String, key.hasPrefix(path + ":") else { continue }
            result[String(key.dropFirst(path.count + 1))] = hash
        }
        return result
    }

    /// Trust statuses of Mely's hooks (`trusted`, `untrusted`, `modified`) from `hooks/list`.
    public static func statuses(fromHooksList response: [String: Any], relayPath: String?) -> [String] {
        (response["data"] as? [[String: Any]] ?? []).flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            .filter { ($0["command"] as? String).map { CodexHookInstaller.isMelyCommand($0, relayPath: relayPath) } ?? false }
            .compactMap { $0["trustStatus"] as? String }
    }

    static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func unquoted(_ s: String) -> String {
        guard s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") else { return s }
        return String(s.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }
}
