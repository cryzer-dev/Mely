import Testing
import Foundation
@testable import MelyCore

/// Runs the built nc-hook binary like Claude Code does.
@Suite(.serialized) struct NCHookProcessTests {
    static let binary = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/debug/nc-hook")

    private func run(_ args: [String], stdin: String, socket: String) throws -> (out: String, status: Int32, seconds: Double) {
        let p = Process()
        p.executableURL = Self.binary
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["MELY_SOCKET_PATH"] = socket
        p.environment = env
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        let start = Date()
        try p.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: out, as: UTF8.self), p.terminationStatus, Date().timeIntervalSince(start))
    }

    private func tempSocket() -> String {
        "/tmp/mely-test-\(UUID().uuidString.prefix(8)).sock"
    }

    @Test func appNotRunningNeverBlocks() throws {
        let permission = #"{"hook_event_name":"PermissionRequest","tool_name":"Bash","session_id":"s"}"#
        let r = try run([], stdin: permission, socket: tempSocket())
        #expect(r.status == 0)
        #expect(r.out.isEmpty)
        #expect(r.seconds < 1)
    }

    @Test func permissionDecisionIsPrinted() throws {
        let path = tempSocket()
        let server = try OneShotServer(path: path, reply: HookDecision.allow.line)
        let r = try run([], stdin: #"{"hook_event_name":"PermissionRequest","tool_name":"Bash","session_id":"s"}"#, socket: path)
        let received = server.waitForRequest()
        #expect(received?["hook_event_name"] as? String == "PermissionRequest")
        #expect(received?["cwd"] as? String != nil)
        #expect(r.status == 0)
        #expect(r.out.contains(#""behavior":"allow""#))
    }

    @Test func askHookIgnoresOtherTools() throws {
        let r = try run(["--ask"], stdin: #"{"hook_event_name":"PreToolUse","tool_name":"Bash"}"#, socket: tempSocket())
        #expect(r.status == 0 && r.out.isEmpty)
    }
}

/// Accepts one connection, records the request line and answers `reply`.
final class OneShotServer: @unchecked Sendable {
    private let fd: Int32
    private let path: String
    private var request: [String: Any]?
    private let done = DispatchSemaphore(value: 0)

    init(path: String, reply: String) throws {
        self.path = path
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard var addr = UnixSocketClient.sockaddrUn(path) else { throw POSIXError(.ENAMETOOLONG) }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0, listen(fd, 1) == 0 else { throw POSIXError(.EADDRINUSE) }
        let listener = fd
        Thread.detachNewThread { [self] in
            let client = accept(listener, nil, nil)
            var data = [UInt8]()
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = recv(client, &buf, buf.count, 0)
                if n <= 0 { break }
                if let nl = buf[0..<n].firstIndex(of: 10) { data += buf[0..<nl]; break }
                data += buf[0..<n]
            }
            request = (try? JSONSerialization.jsonObject(with: Data(data))) as? [String: Any]
            let out = Array((reply + "\n").utf8)
            _ = out.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
            close(client)
            done.signal()
        }
    }

    func waitForRequest() -> [String: Any]? {
        _ = done.wait(timeout: .now() + 5)
        close(fd)
        unlink(path)
        return request
    }
}
