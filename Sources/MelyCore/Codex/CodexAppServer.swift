import Foundation
import OSLog

private let codexLog = Logger(subsystem: "dev.mely.app", category: "codex")

/// Finds the `codex` command and asks its app server one JSON-RPC question: hook hashes
/// (`hooks/list`), plan limits (`account/rateLimits/read`). The server runs over stdio for
/// the one request and is stopped after it.
public enum CodexAppServer {
    public enum Failure: Error, Equatable, LocalizedError {
        case notFound
        case timedOut
        case failed(String)
        /// A JSON-RPC error: its message (e.g. "codex account authentication required…").
        case rpc(String)

        public var errorDescription: String? {
            switch self {
            case .notFound: "Codex не найден"
            case .timedOut: "Codex не ответил за 15 секунд"
            case .failed(let reason): "Codex не запустился: \(reason)"
            case .rpc(let message): message
            }
        }
    }

    public static let timeout: TimeInterval = 15

    /// Where npm, Homebrew and the version managers put `codex`, newest Node first.
    public static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                  fileManager: FileManager = .default) -> [URL] {
        var urls = [".local/bin/codex", ".volta/bin/codex", ".bun/bin/codex", "Library/pnpm/codex", ".npm-global/bin/codex"]
            .map { home.appendingPathComponent($0) }
        urls += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"].map { URL(fileURLWithPath: $0) }
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        let versions = ((try? fileManager.contentsOfDirectory(atPath: nvm.path)) ?? [])
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        urls += versions.map { nvm.appendingPathComponent($0).appendingPathComponent("bin/codex") }
        return urls
    }

    /// The `codex` command, or nil when it is not installed anywhere Mely looks.
    public static func locate(fileManager: FileManager = .default) -> URL? {
        candidates(fileManager: fileManager).first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    /// One request; `codexHome` runs Codex on another config folder (a scratch copy).
    public static func request(_ method: String, params: [String: Any]? = nil, codex: URL, codexHome: URL? = nil,
                               cwd: URL? = nil, timeout: TimeInterval = timeout) async throws -> [String: Any] {
        let boxed = params.map(JSONObject.init)
        let box = try await Task.detached { () throws -> JSONObject in
            JSONObject(try run(method, params: boxed?.value, codex: codex, codexHome: codexHome, cwd: cwd, timeout: timeout))
        }.value
        return box.value
    }

    private static func run(_ method: String, params: [String: Any]?, codex: URL, codexHome: URL?, cwd: URL?,
                            timeout: TimeInterval) throws -> [String: Any] {
        let process = Process()
        process.executableURL = codex
        process.arguments = ["app-server"]
        var env = ProcessInfo.processInfo.environment
        // An npm install is a Node script: its `node` sits next to it (nvm, volta…).
        env["PATH"] = ([codex.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
                       + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init))
            .joined(separator: ":")
        if let codexHome { env["CODEX_HOME"] = codexHome.path }
        process.environment = env
        if let cwd { process.currentDirectoryURL = cwd }
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw Failure.failed(error.localizedDescription) }
        // Stopped after the answer, or by the watchdog: reading then ends.
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer {
            deadline.cancel()
            if process.isRunning { process.terminate() }
            try? input.fileHandleForWriting.close()
        }

        func send(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
            input.fileHandleForWriting.write(data + Data("\n".utf8))
        }
        send(["id": 0, "method": "initialize", "params": ["clientInfo": ["name": "mely", "version": AppInfo.version]]])
        send(["method": "initialized"])
        var message: [String: Any] = ["id": 1, "method": method]
        if let params { message["params"] = params }
        send(message)

        var buffer = Data()
        let reader = output.fileHandleForReading
        while true {
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            buffer += chunk
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer = Data(buffer[buffer.index(after: newline)...])
                guard let reply = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      reply["id"] as? Int == 1 else { continue }
                if let error = reply["error"] as? [String: Any] {
                    throw Failure.rpc(error["message"] as? String ?? "ошибка Codex")
                }
                return reply["result"] as? [String: Any] ?? [:]
            }
        }
        codexLog.error("app-server gave no answer to \(method, privacy: .public)")
        throw Failure.timedOut
    }
}
