// Portions © 2026 Louis Raillé, MIT License — see THIRD_PARTY_NOTICES.md.
import Foundation

/// Answers a blocking request (permission or question). Replying, or dropping the last
/// reference without replying, closes the connection; `nc-hook` then prints nothing and
/// Claude Code asks in the terminal.
public final class HookResponder: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32

    /// Takes ownership of a connected socket (the server's, or a socket pair in previews).
    public init(fd: Int32) { self.fd = fd }

    public func reply(_ decision: HookDecision) {
        lock.lock(); defer { lock.unlock() }
        guard fd >= 0 else { return }
        let bytes = Array((decision.line + "\n").utf8)
        _ = bytes.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        close(fd)
        fd = -1
    }

    /// True while nobody answered and the connection is open.
    public var isPending: Bool {
        lock.lock(); defer { lock.unlock() }
        return fd >= 0
    }

    /// False once `nc-hook` hung up (it timed out, or Claude Code stopped it) or we replied.
    public var isPeerConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        guard fd >= 0 else { return false }
        var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&p, 1, 0) > 0 else { return true }
        if p.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 { return false }
        // Readable with nothing to read: the other end closed.
        var byte: UInt8 = 0
        return recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT) != 0
    }

    deinit {
        if fd >= 0 { close(fd) }
    }
}

/// Unix-socket server for `nc-hook`: same user only (getpeereid), 1 MiB per message,
/// 5 s to send it, 32 connections at most. The socket is 0600 in a 0700 folder.
public final class HookSocketServer: @unchecked Sendable {
    /// Called on a background thread for every request. `responder` is set for blocking
    /// requests (PermissionRequest, AskUserQuestion) and nil for fire-and-forget ones.
    public typealias Handler = @Sendable (_ payload: [String: Any], _ responder: HookResponder?) -> Void

    private let path: String
    private let handler: Handler
    private var listener: Int32 = -1
    private let lock = NSLock()
    private var connections = 0

    private static let maxConnections = 32
    private static let receiveTimeoutSeconds = 5

    public init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    /// Binds and starts accepting on a background thread.
    public func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EBADF) }
        guard var addr = UnixSocketClient.sockaddrUn(path) else { close(fd); throw POSIXError(.ENAMETOOLONG) }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { close(fd); throw POSIXError(.EADDRINUSE) }
        chmod(path, 0o600)
        guard listen(fd, 32) == 0 else { close(fd); throw POSIXError(.EIO) }
        listener = fd
        Thread.detachNewThread { [self] in acceptLoop(fd) }
    }

    public func stop() {
        if listener >= 0 { close(listener); listener = -1 }
        unlink(path)
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            var euid: uid_t = 0, egid: gid_t = 0
            guard getpeereid(client, &euid, &egid) == 0, euid == getuid() else { close(client); continue }
            lock.lock()
            let accepted = connections < Self.maxConnections
            if accepted { connections += 1 }
            lock.unlock()
            guard accepted else { close(client); continue }
            Thread.detachNewThread { [self] in
                handle(client)
                lock.lock(); connections -= 1; lock.unlock()
            }
        }
    }

    private func handle(_ fd: Int32) {
        var tv = timeval(tv_sec: Self.receiveTimeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var raw = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 4096)
        while raw.count <= HookWire.maxPayloadBytes {
            let n = recv(fd, &buf, buf.count, 0)
            guard n > 0 else { break }
            if let nl = buf[0..<n].firstIndex(of: UInt8(ascii: "\n")) {
                raw += buf[0..<nl]
                break
            }
            raw += buf[0..<n]
        }
        guard raw.count <= HookWire.maxPayloadBytes,
              let payload = (try? JSONSerialization.jsonObject(with: Data(raw))) as? [String: Any] else {
            close(fd)
            return
        }
        if Self.isBlocking(payload) {
            handler(payload, HookResponder(fd: fd))
        } else {
            close(fd)
            handler(payload, nil)
        }
    }

    static func isBlocking(_ payload: [String: Any]) -> Bool {
        payload[HookWire.kindKey] as? String == HookWire.kindAskUserQuestion
            || payload["hook_event_name"] as? String == "PermissionRequest"
    }
}
