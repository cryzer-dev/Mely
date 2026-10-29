// Portions © 2026 Louis Raillé, MIT License — see THIRD_PARTY_NOTICES.md.
import Foundation

/// One-line description of a tool call for the island ticker ("Правит · Cart.tsx").
public enum StepLabel {
    static let verbs: [String: String] = [
        "Bash": "Запускает", "Read": "Читает", "Write": "Пишет", "Edit": "Правит", "MultiEdit": "Правит",
        "Glob": "Ищет", "Grep": "Ищет", "LS": "Смотрит", "WebSearch": "Ищет в интернете",
        "WebFetch": "Загружает", "TodoWrite": "Задачи", "Task": "Агент", "NotebookEdit": "Блокнот",
        // Codex
        "apply_patch": "Правит", "update_plan": "План", "spawn_agent": "Агент", "view_image": "Смотрит картинку",
        "web_search": "Ищет в интернете",
    ]
    /// Codex's shell tools; Claude Code's is `Bash`.
    static let shellTools: Set<String> = ["Bash", "shell", "exec_command", "local_shell", "container.exec"]

    public static func label(tool: String, input: [String: Any]) -> String {
        var verb = verbs[tool] ?? tool
        if tool.hasPrefix("mcp__") {
            let parts = tool.dropFirst(5).components(separatedBy: "__")
            verb = parts.count >= 2 ? "\(parts[0]) · \(parts.dropFirst().joined(separator: "__"))" : String(tool.dropFirst(5))
        }
        if shellTools.contains(tool), let cmd = command(input) {
            return "\(bashVerb(cmd)) · \(oneLine(cmd))"
        }
        if tool == "apply_patch", let files = patchFiles(input), let first = files.first {
            let name = URL(fileURLWithPath: first.path).lastPathComponent
            return files.count > 1 ? "\(verb) · \(name) и ещё \(files.count - 1)" : "\(verb) · \(name)"
        }
        if tool == "spawn_agent", let task = (input["message"] as? String) ?? (input["task"] as? String) {
            return "\(verb) · \(oneLine(task))"
        }
        if let file = (input["file_path"] as? String) ?? (input["path"] as? String) ?? (input["notebook_path"] as? String) {
            return "\(verb) · \(URL(fileURLWithPath: file).lastPathComponent)"
        }
        if let pattern = (input["pattern"] as? String) ?? (input["query"] as? String) ?? (input["url"] as? String) {
            return "\(verb) · \(oneLine(pattern))"
        }
        if tool == "Task", let description = input["description"] as? String {
            return "\(verb) · \(oneLine(description))"
        }
        return verb
    }

    /// A shell command as one string: Claude Code sends a string, Codex an argv list.
    public static func command(_ input: [String: Any]) -> String? {
        if let s = input["command"] as? String { return s }
        if let argv = input["command"] as? [String], !argv.isEmpty {
            // `["bash", "-lc", "npm test"]`: the script is what ran.
            if argv.count == 3, ["bash", "sh", "zsh"].contains(argv[0]), argv[1].hasPrefix("-") { return argv[2] }
            return argv.joined(separator: " ")
        }
        if let s = input["cmd"] as? String { return s }
        return nil
    }

    /// The files of a Codex patch (`*** Update File: path` …) with their added and removed
    /// lines; nil when the input holds no patch.
    static func patchFiles(_ input: [String: Any]) -> [(path: String, added: Int, removed: Int, isNew: Bool)]? {
        let text = input.values.compactMap { $0 as? String }.first { $0.contains("*** Begin Patch") }
            ?? (input["command"] as? [String])?.first { $0.contains("*** Begin Patch") }
        guard let text else { return nil }
        var files: [(path: String, added: Int, removed: Int, isNew: Bool)] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let headers = [("*** Update File: ", false), ("*** Add File: ", true), ("*** Delete File: ", false)]
            if let (prefix, isNew) = headers.first(where: { line.hasPrefix($0.0) }) {
                files.append((String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces), 0, 0, isNew))
            } else if !files.isEmpty, !line.hasPrefix("***") {
                if line.hasPrefix("+") { files[files.count - 1].added += 1 }
                else if line.hasPrefix("-") { files[files.count - 1].removed += 1 }
            }
        }
        return files.isEmpty ? nil : files
    }

    /// A more precise verb from a shell command's first word.
    static func bashVerb(_ command: String) -> String {
        let first = command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        switch first {
        case "cat", "bat", "head", "tail", "less", "more", "nl": return "Читает"
        case "rg", "grep", "find", "fd", "ls", "tree", "wc": return "Ищет"
        default: break
        }
        let testRunners = ["pytest", "vitest", "jest", "npm test", "npm run test", "pnpm test", "yarn test",
                           "cargo test", "go test", "swift test", "make test", "playwright test"]
        return testRunners.contains(where: command.contains) ? "Тестирует" : "Запускает"
    }

    /// Collapses whitespace so a multi-line command stays one ticker row.
    public static func oneLine(_ text: String, limit: Int = 60) -> String {
        let collapsed = text.split(whereSeparator: { $0.isNewline || $0 == "\t" }).joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }

    /// The diffs of an editing tool call: one per file (a Codex patch can touch several).
    public static func diffs(tool: String, input: [String: Any]) -> [FileDiff] {
        if tool == "apply_patch" {
            // Counts only: the patch has no full lines around the change.
            return (patchFiles(input) ?? []).filter { $0.added > 0 || $0.removed > 0 }.map {
                FileDiff(path: $0.path, added: $0.added, removed: $0.removed, hunks: [], tooLarge: false, isNewFile: $0.isNew)
            }
        }
        return diff(tool: tool, input: input).map { [$0] } ?? []
    }

    /// The live diff of an editing tool call, or nil when it changes nothing.
    public static func diff(tool: String, input: [String: Any]) -> FileDiff? {
        switch tool {
        case "Edit":
            guard let old = input["old_string"] as? String, let new = input["new_string"] as? String,
                  let path = input["file_path"] as? String, !old.isEmpty || !new.isEmpty else { return nil }
            let d = DiffEngine.fromEdit(old: old, new: new, path: path)
            return d.added > 0 || d.removed > 0 ? d : nil
        case "MultiEdit":
            guard let path = input["file_path"] as? String,
                  let edits = input["edits"] as? [[String: Any]], !edits.isEmpty else { return nil }
            var added = 0, removed = 0, hunks: [DiffHunk] = [], tooLarge = false
            for edit in edits {
                guard let old = edit["old_string"] as? String, let new = edit["new_string"] as? String else { continue }
                let d = DiffEngine.fromEdit(old: old, new: new, path: path)
                added += d.added; removed += d.removed; hunks += d.hunks; tooLarge = tooLarge || d.tooLarge
            }
            guard added > 0 || removed > 0 else { return nil }
            return FileDiff(path: path, added: added, removed: removed, hunks: hunks, tooLarge: tooLarge, isNewFile: false)
        case "Write":
            guard let path = input["file_path"] as? String, let content = input["content"] as? String,
                  !content.isEmpty else { return nil }
            return DiffEngine.fromNew(content: content, path: path)
        default:
            return nil
        }
    }
}
