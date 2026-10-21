import Foundation

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
        let executable = self.executable, workdir = self.workdir
        return AsyncThrowingStream { continuation in
            guard let question = history.last else { continuation.finish(); return }
            let process = Process()
            process.executableURL = executable
            process.arguments = args
            process.currentDirectoryURL = workdir
            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            let task = Task { [weak self] in
                do {
                    try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
                    try process.run()
                    try stdin.fileHandleForWriting.write(contentsOf: Self.inputLine(question))
                    try stdin.fileHandleForWriting.close()
                    var finished = false
                    for try await line in stdout.fileHandleForReading.bytes.lines {
                        switch Self.parse(line) {
                        case .event(let event): continuation.yield(event)
                        case .session(let id): self?.remember(session: id)
                        case .done: finished = true
                        case .failed(let message): throw ClaudeCodeChatError(output: message)
                        case .other: break
                        }
                    }
                    process.waitUntilExit()
                    if !finished {
                        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                        throw ClaudeCodeChatError(output: err.isEmpty ? "Claude Code завершился без ответа" : err)
                    }
                    continuation.finish()
                } catch {
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
