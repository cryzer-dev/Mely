import Foundation
import OSLog
import MelyCore

// nc-hook — relay between Claude Code hooks and Mely.
//
//   nc-hook                 any hook event (event name from the payload)
//   nc-hook --ask           PreToolUse hook for AskUserQuestion (waits for an answer)
//   nc-hook --statusline    statusLine command: forwards rate limits, then runs the
//                           user's previous statusLine command and prints its output
//
// Rule: never get in Claude Code's way. Whatever fails, exit 0; print nothing unless
// the app gave an explicit decision.

/// Names and outcomes only, never content: `log show --predicate 'subsystem == "dev.mely.app" AND category == "relay"'`.
let relayLog = Logger(subsystem: "dev.mely.app", category: "relay")

let args = Array(CommandLine.arguments.dropFirst())
let socketPath = AppInfo.socketURL.path
let raw = FileHandle.standardInput.readDataToEndOfFile()
var payload = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] ?? [:]
relayLog.debug("start \(args.joined(separator: " "), privacy: .public) bytes=\(raw.count, privacy: .public)")

func line(_ object: [String: Any]) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
    return String(decoding: data, as: UTF8.self)
}

func printAndExit(_ text: String?) -> Never {
    if let text { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }
    exit(0)
}

// MARK: statusLine

if args.contains("--statusline") {
    let relay: [String: Any] = [
        HookWire.kindKey: HookWire.kindStatusLine,
        "session_id": payload["session_id"] ?? "",
        "rate_limits": payload["rate_limits"] ?? [:],
    ]
    if let l = line(relay) {
        _ = UnixSocketClient.send(l, to: socketPath, timeout: HookWire.fireAndForgetTimeout, waitForReply: false)
    }
    // Keep the user's own status line working: run the command it had before Mely.
    let previous = AppInfo.dataDirectory.appendingPathComponent("statusline-previous.json")
    if let data = try? Data(contentsOf: previous),
       let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
       let command = obj["command"] as? String, !command.isEmpty {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil {
            input.fileHandleForWriting.write(raw)
            try? input.fileHandleForWriting.close()
            let out = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            FileHandle.standardOutput.write(out)
        }
    }
    exit(0)
}

guard !payload.isEmpty else { exit(0) }

HookContext.enrich(&payload, env: ProcessInfo.processInfo.environment,
                   hostApp: ProcessTree.hostAppBundleId(),
                   cwd: FileManager.default.currentDirectoryPath,
                   tty: ProcessTree.controllingTTY(),
                   claude: ProcessTree.claudeProcess())

// MARK: AskUserQuestion (--ask, PreToolUse)

if args.contains("--ask") {
    guard payload["tool_name"] as? String == "AskUserQuestion" else { exit(0) }
    payload[HookWire.kindKey] = HookWire.kindAskUserQuestion
    guard let request = line(payload),
          let reply = UnixSocketClient.send(request, to: socketPath, timeout: HookWire.askTimeout, waitForReply: true)
    else { exit(0) }
    printAndExit(HookDecision(line: reply).hookOutput(event: "PreToolUse", payload: payload))
}

// MARK: Events

let event = payload["hook_event_name"] as? String ?? ""
guard let request = line(payload) else { exit(0) }

if event == "PermissionRequest" {
    guard let reply = UnixSocketClient.send(request, to: socketPath, timeout: HookWire.permissionTimeout, waitForReply: true)
    else { exit(0) }
    printAndExit(HookDecision(line: reply).hookOutput(event: event, payload: payload))
}

let sent = UnixSocketClient.send(request, to: socketPath, timeout: HookWire.fireAndForgetTimeout, waitForReply: false) != nil
relayLog.info("\(event, privacy: .public) host=\(payload[HookContext.hostBundleId] as? String ?? "-", privacy: .public) entry=\(payload[HookContext.entrypoint] as? String ?? "-", privacy: .public) sent=\(sent, privacy: .public) errno=\(sent ? 0 : UnixSocketClient.lastErrno, privacy: .public)")
exit(0)
