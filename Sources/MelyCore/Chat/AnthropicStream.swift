import Foundation

/// One Server-Sent Event of the Messages API stream.
public struct SSEEvent: Equatable, Sendable {
    public var event: String
    public var data: String

    public init(event: String, data: String) {
        self.event = event
        self.data = data
    }
}

/// Turns stream lines into events: `event:` and `data:` lines, a blank line ends one.
public struct SSEParser: Sendable {
    private var event = ""
    private var data: [String] = []

    public init() {}

    /// Feeds one line (without its newline). Returns an event when the line completes one.
    public mutating func feed(_ line: String) -> SSEEvent? {
        if line.isEmpty {
            defer { event = ""; data = [] }
            guard !data.isEmpty else { return nil }
            return SSEEvent(event: event, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }  // comment / keep-alive
        let (field, value) = Self.split(line)
        switch field {
        case "event": event = value
        case "data": data.append(value)
        default: break
        }
        return nil
    }

    /// `URLSession.AsyncBytes.lines` drops blank lines, so the stream also ends an event
    /// at the next `event:` line. Call this before feeding such a line.
    public mutating func flushIfNewEvent(_ line: String) -> SSEEvent? {
        guard line.hasPrefix("event:"), !data.isEmpty else { return nil }
        return feed("")
    }

    /// Whatever is left at the end of the stream.
    public mutating func finish() -> SSEEvent? { feed("") }

    private static func split(_ line: String) -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        var value = line[line.index(after: colon)...]
        if value.first == " " { value = value.dropFirst() }
        return (String(line[..<colon]), String(value))
    }
}

/// Error the API sent (HTTP status or an `error` event).
public struct AnthropicError: Error, Equatable, Sendable, LocalizedError {
    public let status: Int?
    public let type: String
    public let message: String

    public init(status: Int?, type: String, message: String) {
        self.status = status
        self.type = type
        self.message = message
    }

    /// Parses `{"type":"error","error":{"type":"...","message":"..."}}`.
    public init(status: Int?, body: Data) {
        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let error = obj?["error"] as? [String: Any]
        self.init(status: status, type: error?["type"] as? String ?? "http_error",
                  message: error?["message"] as? String ?? String(decoding: body.prefix(300), as: UTF8.self))
    }

    /// What the user reads in the chat.
    public var errorDescription: String? {
        switch (status, type) {
        case (401, _), (_, "authentication_error"): "Ключ API не подходит. Проверьте его в настройках чата."
        case (403, _), (_, "permission_error"): "У ключа нет доступа к этой модели."
        case (429, _), (_, "rate_limit_error"): "Слишком много запросов. Попробуйте через минуту."
        case (529, _), (_, "overloaded_error"): "Claude сейчас перегружен. Попробуйте ещё раз чуть позже."
        case (413, _), (_, "request_too_large"): "Вложения слишком большие для одного запроса."
        default: message.isEmpty ? "Ошибка API" : message
        }
    }
}

/// Builds the assistant message from stream events. Content blocks are kept whole
/// (thinking blocks with their signatures) so the next request can echo them back.
public struct MessageAccumulator: Sendable {
    /// Raw content blocks by index, as JSON objects.
    public private(set) var blocks: [Int: JSONObject] = [:]
    public private(set) var model: String?
    public private(set) var stopReason: String?
    public private(set) var error: AnthropicError?
    public private(set) var isFinished = false
    /// Claude Code with tools streams one API message per step (search, then answer):
    /// later messages continue the block numbering instead of overwriting it.
    private var indexOffset = 0
    /// First block index of each streamed message.
    private var messageStarts: [Int] = [0]

    public init() {}

    /// A web search is running: the last block is a search call with no answer after it yet.
    public var isSearching: Bool {
        guard let last = ordered.last else { return false }
        let type = last["type"] as? String
        if type == "server_tool_use" { return true }
        return type == "tool_use" && (last["name"] as? String)?.lowercased().contains("search") == true
    }

    /// The visible answer so far: every text block. After a mid-stream fallback the
    /// partial stays and the fallback model continues it, so nothing is dropped.
    public var text: String {
        // Blocks of one message join as they are (citations split a sentence); separate
        // messages (a step before a search, then the answer) get a paragraph break.
        var out = ""
        var lastMessage: Int?
        for index in blocks.keys.sorted() {
            guard let block = blocks[index]?.value, block["type"] as? String == "text",
                  let text = block["text"] as? String, !text.isEmpty else { continue }
            let message = messageStarts.last { $0 <= index } ?? 0
            if let lastMessage, lastMessage != message, !out.isEmpty { out += "\n\n" }
            out += text
            lastMessage = message
        }
        return out
    }

    public var wasRefused: Bool { stopReason == "refusal" }

    var ordered: [[String: Any]] { blocks.keys.sorted().compactMap { blocks[$0]?.value } }

    /// Content to echo in the history. After a mid-output fallback, model-internal blocks
    /// before the last `fallback` marker are omitted; the marker itself is dropped.
    public var historyContent: [[String: Any]] {
        let all = ordered
        let boundary = all.lastIndex { $0["type"] as? String == "fallback" } ?? -1
        let internalTypes: Set<String> = ["thinking", "redacted_thinking", "tool_use", "server_tool_use"]
        return all.enumerated().compactMap { index, block in
            let type = block["type"] as? String ?? ""
            if type == "fallback" { return nil }
            if index < boundary, internalTypes.contains(type) { return nil }
            return block
        }
    }

    /// Applies one event. Unknown events are ignored (the API adds new ones).
    public mutating func apply(_ event: SSEEvent) {
        guard let data = event.data.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        switch obj["type"] as? String ?? event.event {
        case "message_start":
            model = (obj["message"] as? [String: Any])?["model"] as? String
            indexOffset = (blocks.keys.max() ?? -1) + 1
            if indexOffset > 0 { messageStarts.append(indexOffset) }
        case "content_block_start":
            guard let index = (obj["index"] as? Int).map({ $0 + indexOffset }),
                  var block = obj["content_block"] as? [String: Any] else { return }
            if block["type"] as? String == "tool_use" { block["input"] = block["input"] ?? [:] }
            blocks[index] = JSONObject(block)
        case "content_block_delta":
            guard let index = (obj["index"] as? Int).map({ $0 + indexOffset }), var block = blocks[index]?.value,
                  let delta = obj["delta"] as? [String: Any] else { return }
            switch delta["type"] as? String {
            case "text_delta": block["text"] = (block["text"] as? String ?? "") + (delta["text"] as? String ?? "")
            case "thinking_delta": block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
            case "signature_delta": block["signature"] = (block["signature"] as? String ?? "") + (delta["signature"] as? String ?? "")
            default: break
            }
            blocks[index] = JSONObject(block)
        case "message_delta":
            if let reason = (obj["delta"] as? [String: Any])?["stop_reason"] as? String { stopReason = reason }
        case "message_stop":
            isFinished = true
        case "error":
            let e = obj["error"] as? [String: Any]
            error = AnthropicError(status: nil, type: e?["type"] as? String ?? "error",
                                   message: e?["message"] as? String ?? "Ошибка потока")
            isFinished = true
        default:
            break
        }
    }
}
