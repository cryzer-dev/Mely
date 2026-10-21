import Foundation

/// Host context `nc-hook` adds to every payload, so the app knows where the session runs.
public enum HookContext {
    /// Keys added to the payload.
    public static let termProgram = "term_program"
    public static let terminalEmulator = "terminal_emulator"
    public static let bundleId = "bundle_id"
    public static let hostBundleId = "host_bundle_id"
    public static let itermSessionId = "iterm_session_id"
    public static let termSessionId = "term_session_id"
    public static let entrypoint = "claude_entrypoint"
    /// Controlling terminal of the `claude` process ("/dev/ttys004"), to pick the Terminal tab.
    public static let tty = "tty"
    /// The Claude Code process (pid and start time): the session ends when it exits.
    public static let claudePid = "claude_pid"
    public static let claudeStart = "claude_start"

    /// Adds host context without overwriting what the payload already has.
    /// - Parameters:
    ///   - hostApp: bundle id of the nearest parent process living inside an `.app`
    ///     (found by walking the process tree); it identifies JetBrains IDEs, whose
    ///     terminal sets neither `TERM_PROGRAM` nor, reliably, `__CFBundleIdentifier`.
    public static func enrich(_ payload: inout [String: Any], env: [String: String],
                              hostApp: String?, cwd: String, tty: String? = nil, claude: ProcessIdentity? = nil) {
        func setDefault(_ key: String, _ value: String?) {
            guard payload[key] == nil, let value, !value.isEmpty else { return }
            payload[key] = value
        }
        setDefault(termProgram, env["TERM_PROGRAM"])
        setDefault(terminalEmulator, env["TERMINAL_EMULATOR"])
        setDefault(bundleId, env["__CFBundleIdentifier"])
        setDefault(hostBundleId, hostApp)
        setDefault(itermSessionId, env["ITERM_SESSION_ID"])
        setDefault(termSessionId, env["TERM_SESSION_ID"])
        setDefault(entrypoint, env["CLAUDE_CODE_ENTRYPOINT"])
        setDefault(Self.tty, tty)
        if let claude, payload[claudePid] == nil {
            payload[claudePid] = Int(claude.pid)
            payload[claudeStart] = claude.start
        }
        if (payload["cwd"] as? String)?.isEmpty ?? true {
            payload["cwd"] = cwd
        }
    }

    /// Path of the outermost `.app` bundle containing `executablePath`, if any
    /// (`/Applications/WebStorm.app/Contents/jbr/…/java` → `/Applications/WebStorm.app`).
    /// Outermost, so a helper nested inside an IDE bundle still means the IDE.
    public static func appBundlePath(containing executablePath: String) -> String? {
        guard let range = executablePath.range(of: ".app/") else { return nil }
        return String(executablePath[..<range.lowerBound]) + ".app"
    }
}
