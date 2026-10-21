import Foundation

/// Where a Claude Code session runs, as reported by `nc-hook`.
public struct HookOrigin: Equatable, Sendable {
    public var sessionId: String
    public var cwd: String
    public var termProgram: String
    public var terminalEmulator: String
    public var bundleId: String
    public var hostBundleId: String
    public var itermSessionId: String
    public var termSessionId: String
    public var tty: String
    /// `CLAUDE_CODE_ENTRYPOINT`: "cli", "claude-desktop" (Code tab of the Claude app)…
    public var entrypoint: String
    /// The Claude Code process; nil from an older `nc-hook`.
    public var process: ProcessIdentity?

    public var projectName: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || cwd.isEmpty ? "Сессия" : name
    }

    public init(_ p: [String: Any]) {
        func s(_ k: String) -> String { p[k] as? String ?? "" }
        sessionId = s("session_id").isEmpty ? "unknown" : s("session_id")
        cwd = s("cwd")
        termProgram = s(HookContext.termProgram)
        terminalEmulator = s(HookContext.terminalEmulator)
        bundleId = s(HookContext.bundleId)
        hostBundleId = s(HookContext.hostBundleId)
        itermSessionId = s(HookContext.itermSessionId)
        termSessionId = s(HookContext.termSessionId)
        tty = s(HookContext.tty)
        entrypoint = s(HookContext.entrypoint)
        if let pid = (p[HookContext.claudePid] as? NSNumber)?.int32Value,
           let start = (p[HookContext.claudeStart] as? NSNumber)?.doubleValue {
            process = ProcessIdentity(pid: pid, start: start)
        }
    }
}

/// A raw JSON object carried across actors. Payloads come from our own relay and are
/// only read after decoding.
public struct JSONObject: @unchecked Sendable {
    public let value: [String: Any]
    public init(_ value: [String: Any]) { self.value = value }
    public subscript(key: String) -> Any? { value[key] }
}

/// A Claude Code hook event, decoded from the relay's payload.
public enum HookEvent: Sendable {
    case sessionStart
    case sessionEnd
    case userPrompt(String)
    case toolStarted(tool: String, input: JSONObject)
    case toolFinished(tool: String, input: JSONObject, failed: Bool)
    case permissionRequest(tool: String, input: JSONObject, suggestions: JSONObject)
    case question(input: JSONObject)
    case notification(type: String, message: String)
    case stop(lastMessage: String?)
    case stopFailure(String?)
    case subagentStarted
    case subagentStopped
    case statusLine(rateLimits: JSONObject)
    case unknown(String)

    /// Case name without content, safe for logs.
    public var name: String {
        switch self {
        case .sessionStart: "sessionStart"
        case .sessionEnd: "sessionEnd"
        case .userPrompt: "userPrompt"
        case .toolStarted(let tool, _): "toolStarted(\(tool))"
        case .toolFinished(let tool, _, let failed): "toolFinished(\(tool)\(failed ? ", failed" : ""))"
        case .permissionRequest(let tool, _, _): "permissionRequest(\(tool))"
        case .question: "question"
        case .notification(let type, _): "notification(\(type))"
        case .stop: "stop"
        case .stopFailure: "stopFailure"
        case .subagentStarted: "subagentStarted"
        case .subagentStopped: "subagentStopped"
        case .statusLine: "statusLine"
        case .unknown(let name): "unknown(\(name))"
        }
    }

    /// Decodes a request. Never fails: unknown names become `.unknown`.
    public static func decode(_ p: [String: Any]) -> (HookEvent, HookOrigin) {
        let origin = HookOrigin(p)
        let input = JSONObject(p["tool_input"] as? [String: Any] ?? [:])
        let tool = p["tool_name"] as? String ?? ""
        switch p[HookWire.kindKey] as? String {
        case HookWire.kindStatusLine:
            return (.statusLine(rateLimits: JSONObject(p["rate_limits"] as? [String: Any] ?? [:])), origin)
        case HookWire.kindAskUserQuestion:
            return (.question(input: input), origin)
        default:
            break
        }
        let name = p["hook_event_name"] as? String ?? ""
        let event: HookEvent
        switch name {
        case "SessionStart": event = .sessionStart
        case "SessionEnd": event = .sessionEnd
        case "UserPromptSubmit": event = .userPrompt(p["prompt"] as? String ?? "")
        case "PreToolUse": event = .toolStarted(tool: tool, input: input)
        case "PostToolUse": event = .toolFinished(tool: tool, input: input, failed: false)
        case "PostToolUseFailure": event = .toolFinished(tool: tool, input: input, failed: true)
        case "PermissionRequest":
            if tool == "AskUserQuestion" {
                event = .question(input: input)
            } else {
                event = .permissionRequest(tool: tool, input: input,
                                           suggestions: JSONObject(["items": p["permission_suggestions"] ?? []]))
            }
        case "Notification":
            event = .notification(type: p["notification_type"] as? String ?? "", message: p["message"] as? String ?? "")
        case "Stop": event = .stop(lastMessage: p["last_assistant_message"] as? String)
        case "StopFailure": event = .stopFailure((p["error"] as? String) ?? (p["message"] as? String))
        case "SubagentStart": event = .subagentStarted
        case "SubagentStop": event = .subagentStopped
        default: event = .unknown(name)
        }
        return (event, origin)
    }
}
