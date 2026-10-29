import Foundation

/// The line protocol between `nc-hook` and the app: one JSON object per line over the
/// Unix socket `AppInfo.socketURL`. Requests are Claude Code's hook payload enriched
/// with host context; blocking requests get one decision line back.
public enum HookWire {
    /// `mely_kind` values for requests that are not plain hook events.
    public static let kindKey = "mely_kind"
    public static let kindStatusLine = "statusline"
    public static let kindAskUserQuestion = "ask_user_question"
    /// Which agent sent the event (`nc-hook --agent codex`); absent for Claude Code.
    public static let agentKey = "mely_agent"

    /// Fire-and-forget events: connect + send must finish in this time or we give up.
    public static let fireAndForgetTimeout: TimeInterval = 0.3
    /// PermissionRequest: just under the 120 s hook timeout written in settings.json.
    public static let permissionTimeout: TimeInterval = 118
    /// AskUserQuestion (--ask): just under its 130 s hook timeout.
    public static let askTimeout: TimeInterval = 125

    public static let maxPayloadBytes = 1_048_576
}

/// What the app answers to a blocking request.
public enum HookDecision: Equatable, Sendable {
    case allow
    /// Allow and let Claude Code persist the rule it suggested.
    case always
    case deny
    /// Answers to AskUserQuestion, keyed by question text. A multi-select answer is a list.
    case answer([String: AnswerValue])
    /// Let Claude Code ask in the terminal.
    case ask

    public enum AnswerValue: Equatable, Sendable {
        case single(String)
        case multiple([String])

        var json: Any {
            switch self {
            case .single(let s): s
            case .multiple(let a): a
            }
        }
    }

    /// The line the app sends.
    public var line: String {
        var obj: [String: Any] = [:]
        switch self {
        case .allow: obj["permissionDecision"] = "allow"
        case .always: obj["permissionDecision"] = "always"
        case .deny: obj["permissionDecision"] = "deny"
        case .ask: obj["permissionDecision"] = "ask"
        case .answer(let answers):
            obj["permissionDecision"] = "answer"
            obj["answers"] = answers.mapValues(\.json)
        }
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Parses the app's line. Anything unknown means "ask in the terminal".
    public init(line: String) {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let decision = obj["permissionDecision"] as? String else {
            self = .ask
            return
        }
        switch decision {
        case "allow": self = .allow
        case "always": self = .always
        case "deny": self = .deny
        case "answer":
            var answers: [String: AnswerValue] = [:]
            for (question, value) in obj["answers"] as? [String: Any] ?? [:] {
                if let s = value as? String { answers[question] = .single(s) }
                else if let a = value as? [String] { answers[question] = .multiple(a) }
            }
            self = .answer(answers)
        default: self = .ask
        }
    }

    /// What `nc-hook` prints on stdout for Claude Code, or nil to print nothing (Claude Code
    /// then behaves as if no hook were installed and asks in the terminal).
    /// - Parameter event: `PermissionRequest`, or `PreToolUse` for the `--ask` hook.
    public func hookOutput(event: String, payload: [String: Any]) -> String? {
        let output: [String: Any]
        switch self {
        case .ask:
            return nil
        case .allow, .always, .deny:
            // Allow/deny only make sense for a permission request.
            guard event == "PermissionRequest" else { return nil }
            var decision: [String: Any]
            // Codex refuses a decision with `updatedPermissions` ("fail closed"): no «Всегда» there.
            let canPersist = Agent(wire: payload[HookWire.agentKey] as? String) == .claude
            switch self {
            case .deny: decision = ["behavior": "deny", "message": "Отклонено в Mely"]
            case .always where canPersist:
                decision = ["behavior": "allow", "updatedPermissions": payload["permission_suggestions"] ?? []]
            default: decision = ["behavior": "allow"]
            }
            output = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        case .answer(let answers):
            let questions = (payload["tool_input"] as? [String: Any])?["questions"] ?? []
            let updatedInput: [String: Any] = ["questions": questions, "answers": answers.mapValues(\.json)]
            if event == "PreToolUse" {
                output = ["hookSpecificOutput": ["hookEventName": "PreToolUse",
                                                 "permissionDecision": "allow",
                                                 "updatedInput": updatedInput]]
            } else {
                output = ["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                                 "decision": ["behavior": "allow", "updatedInput": updatedInput]]]
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
