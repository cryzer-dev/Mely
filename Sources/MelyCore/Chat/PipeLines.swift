import Foundation

/// Lines from a pipe, as they come. Instead of `FileHandle.bytes.lines`: those readers
/// take turns, so one waiting on a quiet pipe (the Now Playing adapter between songs)
/// holds every other back, and the chat never got a line.
public enum PipeLines {
    /// Ends at EOF. Cancelling the stream stops reading.
    public static func lines(_ handle: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuation in
            let buffer = LineBuffer()
            handle.readabilityHandler = { h in
                let data = h.availableData
                guard !data.isEmpty else {
                    h.readabilityHandler = nil
                    if let rest = buffer.flush() { continuation.yield(rest) }
                    continuation.finish()
                    return
                }
                for line in buffer.append(data) { continuation.yield(line) }
            }
            continuation.onTermination = { _ in handle.readabilityHandler = nil }
        }
    }
}

/// Splits bytes into lines without the newline; a trailing "\r" is dropped too.
final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.withLock {
            pending.append(data)
            var lines: [String] = []
            while let newline = pending.firstIndex(of: 0x0A) {
                lines.append(Self.text(pending[pending.startIndex..<newline]))
                pending.removeSubrange(pending.startIndex...newline)
            }
            return lines
        }
    }

    /// Collects raw bytes, keeping only the last `limit` of them (stderr for an error message).
    func keep(_ data: Data, last limit: Int) {
        lock.withLock {
            pending.append(data)
            if pending.count > limit { pending = Data(pending.suffix(limit)) }
        }
    }

    /// What is left after EOF, if anything.
    func flush() -> String? {
        lock.withLock {
            defer { pending = Data() }
            return pending.isEmpty ? nil : Self.text(pending)
        }
    }

    private static func text(_ bytes: Data) -> String {
        var s = String(decoding: bytes, as: UTF8.self)
        if s.hasSuffix("\r") { s.removeLast() }
        return s
    }
}
