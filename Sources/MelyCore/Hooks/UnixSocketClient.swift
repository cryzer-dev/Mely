import Foundation

/// Minimal blocking Unix-socket client for `nc-hook`. Every failure returns nil:
/// the relay must never get in Claude Code's way.
public enum UnixSocketClient {
    /// errno of the last failure, for the relay's diagnostic log (one process, one call).
    nonisolated(unsafe) public static var lastErrno: Int32 = 0

    /// Sends one line; if `waitForReply`, returns the first line received within `timeout`.
    public static func send(_ line: String, to path: String, timeout: TimeInterval, waitForReply: Bool) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { lastErrno = errno; return nil }
        defer { close(fd) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        guard var addr = sockaddrUn(path) else { return nil }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { lastErrno = errno; return nil }

        let bytes = Array((line + "\n").utf8)
        var sent = 0
        while sent < bytes.count {
            let n = bytes[sent...].withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
            guard n > 0 else { return nil }
            sent += n
        }
        guard waitForReply else { return "" }

        var reply = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 4096)
        while reply.count < HookWire.maxPayloadBytes {
            let n = recv(fd, &buf, buf.count, 0)
            guard n > 0 else { break }
            if let nl = buf[0..<n].firstIndex(of: UInt8(ascii: "\n")) {
                reply.append(contentsOf: buf[0..<nl])
                break
            }
            reply.append(contentsOf: buf[0..<n])
        }
        return reply.isEmpty ? nil : String(decoding: reply, as: UTF8.self)
    }

    /// A `sockaddr_un` for `path`, or nil if the path does not fit (103 bytes on macOS).
    public static func sockaddrUn(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count <= capacity else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = UInt8(bitPattern: b) }
        }
        return addr
    }
}
