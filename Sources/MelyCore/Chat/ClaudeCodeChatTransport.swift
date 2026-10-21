import Foundation
import os

private let log = Logger(subsystem: "dev.mely.app", category: "chat")

/// Answers through the user's Claude subscription: the local Claude Code CLI in print
/// mode, no key needed. It runs `--restricted` with web search as its only tool, in Mely's
/// own folder, so it only talks and searches, and the user's hooks (Mely's among them)
/// do not fire for the chat.
/// One process per question; `--resume` carries the conversation.
public final class ClaudeCodeChatTransport: ChatTransport, @unchecked Sendable {
    public let executable: URL
    public let workdir: URL
    private let lock = NSLock()
    private var sessionId: String?

    public init(executable: URL, workdir: URL = AppInfo.dataDirectory.appendingPathComponent("chat", isDirectory: true)) {
        self.executable = executable
        self.workdir = workdir
    }

    public func reset() {
        lock.withLock { sessionId = nil }
    }

    private func remember(session id: String) {
        lock.withLock { sessionId = id }
    }

    static let system = """
        Ты помощник в приложении Mely, которое живёт в челке Mac. Отвечай на языке вопроса, \
        кратко и по делу: окно небольшое. Используй Markdown, когда он помогает: списки, код. \
        Из инструментов у тебя только веб-поиск: ищи для свежих фактов, новостей и цен.
        Короткий вопрос без своей темы продолжает предыдущий: «а сейчас?», «а за месяц?» — про то же, \
        о чём говорили. Mely — только место, где идёт разговор, а не его тема: не ищи и не рассказывай \
        про Mely, пока о ней не спросили прямо.
        """

    /// Arguments for one question.
    func arguments(model: ChatModel, resume: String?) -> [String] {
        // Only web search: no files, no commands. Allowed up front, so print mode never asks.
        var args = ["-p", "--restricted", "--tools", "WebSearch", "--allowedTools", "WebSearch", "--strict-mcp-config",
                    "--input-format", "stream-json", "--output-format", "stream-json",
                    "--verbose", "--include-partial-messages",
                    "--system-prompt", Self.system, "--model", model.rawValue]
        if let resume { args += ["--resume", resume] }
        return args
    }

    /// The stdin line: the last question with its attachments.
    static func inputLine(_ question: ChatTurn) -> Data {
        let message: [String: Any] = ["type": "user",
                                      "message": ["role": "user", "content": question.content.map(\.value)]]
        var data = (try? JSONSerialization.data(withJSONObject: message)) ?? Data()
        data.append(0x0A)
        return data
    }

    /// One stdout line → a stream event for `MessageAccumulator`, a session id, or the end.
    enum Line: Equatable {
        case event(SSEEvent)
        case session(String)
        case done
        case failed(String)
        case other
    }

    static func parse(_ line: String) -> Line {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .other }
        switch obj["type"] as? String {
        case "stream_event":
            guard let event = obj["event"] as? [String: Any],
                  let raw = try? JSONSerialization.data(withJSONObject: event) else { return .other }
            return .event(SSEEvent(event: event["type"] as? String ?? "", data: String(decoding: raw, as: UTF8.self)))
        case "system" where obj["subtype"] as? String == "init":
            return (obj["session_id"] as? String).map(Line.session) ?? .other
        case "result":
            if obj["is_error"] as? Bool == true {
                let text = obj["result"] as? String ?? (obj["errors"] as? [String])?.joined(separator: "\n") ?? ""
                return .failed(text)
            }
            return .done
        default:
            return .other
        }
    }

    public func stream(apiKey: String, model: ChatModel, history: [ChatTurn]) -> AsyncThrowingStream<SSEEvent, Error> {
        let resume = history.count > 1 ? lock.withLock { sessionId } : nil
        let args = arguments(model: model, resume: resume)
        let executable = self.executable, workdir = self.workdir, silenceLimit = self.silenceLimit
        return AsyncThrowingStream { continuation in
            guard let question = history.last else { continuation.finish(); return }
            let process = Process()
            process.executableURL = executable
            process.arguments = args
            process.currentDirectoryURL = workdir
            process.environment = Self.environment(for: executable)
            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            // Read at once: a full stderr pipe would stop Claude Code mid-answer.
            let errors = LineBuffer()
            stderr.fileHandleForReading.readabilityHandler = { h in
                let data = h.availableData
                if data.isEmpty { h.readabilityHandler = nil } else { errors.keep(data, last: 64 * 1024) }
            }
            let activity = Activity()
            let task = Task { [weak self] in
                // Silence for `silenceLimit` ends the process, and with it the lines below.
                let watchdog = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        if activity.silence > silenceLimit { activity.timedOut = true; process.terminate(); return }
                    }
                }
                defer { watchdog.cancel() }
                do {
                    try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
                    try process.run()
                    log.info("cli launched pid=\(process.processIdentifier) resume=\(resume != nil)")
                    try stdin.fileHandleForWriting.write(contentsOf: Self.inputLine(question))
                    try stdin.fileHandleForWriting.close()
                    var finished = false
                    var events = 0
                    lines: for await line in PipeLines.lines(stdout.fileHandleForReading) {
                        activity.touch()
                        switch Self.parse(line) {
                        case .event(let event):
                            events += 1
                            continuation.yield(event)
                        case .session(let id): self?.remember(session: id)
                        case .done:
                            finished = true
                            break lines
                        case .failed(let message): throw ClaudeCodeChatError(output: message)
                        case .other: break
                        }
                    }
                    log.info("cli done: \(events) events, result=\(finished)")
                    if finished {
                        // The answer is complete; whatever Claude Code still does after it is not waited for.
                        continuation.finish()
                        Self.terminate(process, after: .seconds(2))
                        return
                    }
                    if activity.timedOut { throw ClaudeCodeChatError.silent }
                    try await Self.waitForExit(process)
                    let err = errors.flush() ?? ""
                    throw ClaudeCodeChatError(output: err.isEmpty ? "Claude Code завершился без ответа" : err)
                } catch {
                    log.error("cli failed: \(error.localizedDescription, privacy: .public)")
                    if process.isRunning { process.terminate() }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                if process.isRunning { process.terminate() }
            }
        }
    }

    /// How long Claude Code may print nothing before the question counts as unanswered.
    /// Searches stream partial messages, so a minute of silence is a stuck process.
    public var silenceLimit: TimeInterval = 60

    /// A GUI app gets launchd's short PATH: an npm `claude` (`#!/usr/bin/env node`) needs
    /// its own folder and the usual install places on it.
    static func environment(for executable: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        return env
    }

    private static func terminate(_ process: Process, after delay: Duration) {
        Task {
            try? await Task.sleep(for: delay)
            if process.isRunning { process.terminate() }
        }
    }

    /// Without blocking a thread of the pool, as `waitUntilExit()` does.
    private static func waitForExit(_ process: Process) async throws {
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    }

    /// Where `claude` is: a GUI app does not get the shell's PATH, so look in the usual
    /// install places (Homebrew, the native installer, npm under nvm/fnm/volta/bun/pnpm/mise,
    /// the copy inside Claude Desktop), then ask the user's own shell, interactive, so
    /// `.zshrc` runs too.
    public static func locate(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                              askShell: Bool = true) -> URL? {
        let fm = FileManager.default
        if let path = candidates(home: home).first(where: { fm.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        guard askShell, let path = shellLookup(), fm.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// The places to try, best first. Version folders are expanded, newest first.
    static func candidates(home: URL) -> [String] {
        let h = home.path
        var list = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                    "\(h)/.local/bin/claude", "\(h)/.claude/local/claude",
                    "\(h)/.npm-global/bin/claude", "\(h)/.npm/bin/claude",
                    "\(h)/.volta/bin/claude", "\(h)/.bun/bin/claude",
                    "\(h)/Library/pnpm/claude", "\(h)/.local/share/pnpm/claude",
                    "\(h)/.asdf/shims/claude", "\(h)/.local/share/mise/shims/claude",
                    "/opt/local/bin/claude"]
        list += versions(in: "\(h)/.nvm/versions/node", then: "bin/claude")
        list += versions(in: "\(h)/.local/share/fnm/node-versions", then: "installation/bin/claude")
        list += versions(in: "\(h)/Library/Application Support/fnm/node-versions", then: "installation/bin/claude")
        list += versions(in: "\(h)/.local/share/mise/installs/node", then: "bin/claude")
        list += versions(in: "\(h)/.asdf/installs/nodejs", then: "bin/claude")
        // Claude Desktop carries its own Claude Code: claude-code/<version>/<hash>/claude.app.
        for version in versions(in: "\(h)/Library/Application Support/Claude/claude-code", then: "") {
            let builds = (try? FileManager.default.contentsOfDirectory(atPath: version)) ?? []
            list += builds.sorted().map { "\(version)/\($0)/claude.app/Contents/MacOS/claude" }
        }
        return list
    }

    /// `<folder>/<each version>/<rest>`, the newest version first.
    private static func versions(in folder: String, then rest: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return names.filter { !$0.hasPrefix(".") }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { rest.isEmpty ? "\(folder)/\($0)" : "\(folder)/\($0)/\(rest)" }
    }

    /// Asks the user's login shell, interactive so `.zshrc`/`.bashrc` set PATH up; gives
    /// up after 5 seconds.
    private static func shellLookup() -> String? {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: shellPath)
        shell.arguments = ["-ilc", "command -v claude"]
        let out = Pipe()
        shell.standardOutput = out
        shell.standardError = FileHandle.nullDevice
        shell.standardInput = FileHandle.nullDevice
        guard (try? shell.run()) != nil else { return nil }
        let deadline = Date().addingTimeInterval(5)
        while shell.isRunning, Date() < deadline { usleep(50_000) }
        if shell.isRunning { shell.terminate(); return nil }
        // Interactive shells may print greetings: take the last line that is a path.
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") }
    }
}

/// A failure Claude Code printed; the common ones get a plain explanation.
public struct ClaudeCodeChatError: Error, Equatable, LocalizedError {
    public let output: String

    public init(output: String) {
        self.output = output
    }

    /// Nothing printed for `silenceLimit`.
    public static let silent = ClaudeCodeChatError(output: "Claude Code не ответил за минуту")

    public var errorDescription: String? {
        let t = output.lowercased()
        if t.contains("login") || t.contains("not logged") || t.contains("invalid api key") || t.contains("oauth") {
            return "Claude Code не вошёл в аккаунт. Запустите `claude` в терминале и выполните /login."
        }
        if t.contains("usage limit") || t.contains("limit reached") || t.contains("rate limit") {
            return "Лимит плана Claude исчерпан. Дождитесь сброса или переключите чат на ключ API."
        }
        let line = output.split(separator: "\n").first.map(String.init) ?? ""
        return line.isEmpty ? "Claude Code не ответил." : line
    }
}

/// When the process last printed, and whether the watchdog gave up on it.
private final class Activity: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date()
    private var _timedOut = false

    func touch() { lock.withLock { last = Date() } }
    var silence: TimeInterval { lock.withLock { Date().timeIntervalSince(last) } }
    var timedOut: Bool {
        get { lock.withLock { _timedOut } }
        set { lock.withLock { _timedOut = newValue } }
    }
}
