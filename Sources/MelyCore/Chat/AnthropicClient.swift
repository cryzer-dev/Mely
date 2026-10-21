import Foundation

/// Models offered in the chat settings.
public enum ChatModel: String, CaseIterable, Identifiable, Sendable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-4-5"

    public static let `default` = ChatModel.opus
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .opus: "Claude Opus 5.5"
        case .sonnet: "Claude Sonnet 5.5"
        case .haiku: "Claude Haiku 4.5"
        }
    }

    public var note: String {
        switch self {
        case .opus: "самая умная"
        case .sonnet: "быстрее и дешевле"
        case .haiku: "самая быстрая"
        }
    }

    /// Server-side fallback on a safety decline (`fallbacks: "default"`); Haiku has none.
    var supportsFallbacks: Bool { self != .haiku }

    /// Web search with dynamic filtering on the current models; the basic one on Haiku.
    var webSearchTool: [String: Any] {
        ["type": self == .haiku ? "web_search_20250305" : "web_search_20260209", "name": "web_search", "max_uses": 5]
    }
}

/// A file attached to a question.
public struct ChatAttachment: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case image, pdf, text }

    public let id: UUID
    public let name: String
    public let kind: Kind
    public let mediaType: String
    public let data: Data

    public init(name: String, kind: Kind, mediaType: String, data: Data) {
        self.id = UUID()
        self.name = name
        self.kind = kind
        self.mediaType = mediaType
        self.data = data
    }

    /// The API takes images up to 5 MB and requests up to 32 MB.
    public static let maxImageBytes = 5 * 1024 * 1024
    public static let maxFileBytes = 24 * 1024 * 1024

    public enum LoadError: Error, Equatable, LocalizedError {
        case unsupported(String), tooLarge(String), unreadable(String)
        public var errorDescription: String? {
            switch self {
            case .unsupported(let n): "«\(n)»: такой файл Claude не прочитает (картинки, PDF и текст подходят)."
            case .tooLarge(let n): "«\(n)» слишком большой."
            case .unreadable(let n): "Не удалось прочитать «\(n)»."
            }
        }
    }

    /// Reads a dropped file: images and PDF as they are, anything that decodes as UTF-8 as text.
    public static func load(_ url: URL) throws -> ChatAttachment {
        let name = url.lastPathComponent
        guard let data = try? Data(contentsOf: url) else { throw LoadError.unreadable(name) }
        let images = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp"]
        let ext = url.pathExtension.lowercased()
        if let type = images[ext] {
            guard data.count <= maxImageBytes else { throw LoadError.tooLarge(name) }
            return ChatAttachment(name: name, kind: .image, mediaType: type, data: data)
        }
        guard data.count <= maxFileBytes else { throw LoadError.tooLarge(name) }
        if ext == "pdf" { return ChatAttachment(name: name, kind: .pdf, mediaType: "application/pdf", data: data) }
        guard String(data: data, encoding: .utf8) != nil else { throw LoadError.unsupported(name) }
        return ChatAttachment(name: name, kind: .text, mediaType: "text/plain", data: data)
    }

    /// The content block for the request.
    var block: [String: Any] {
        switch kind {
        case .image:
            return ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": data.base64EncodedString()]]
        case .pdf:
            return ["type": "document", "title": name,
                    "source": ["type": "base64", "media_type": mediaType, "data": data.base64EncodedString()]]
        case .text:
            return ["type": "document", "title": name,
                    "source": ["type": "text", "media_type": "text/plain", "data": String(decoding: data, as: UTF8.self)]]
        }
    }
}

/// One turn of the API history.
public struct ChatTurn: Sendable {
    public enum Role: String, Sendable { case user, assistant }
    public let role: Role
    /// Content blocks as sent (user) or received (assistant).
    public let content: [JSONObject]

    public init(role: Role, content: [[String: Any]]) {
        self.role = role
        self.content = content.map(JSONObject.init)
    }

    /// A question: attachments first, then the text (the API reads files best that way).
    public static func question(_ text: String, attachments: [ChatAttachment]) -> ChatTurn {
        var blocks = attachments.map(\.block)
        if !text.isEmpty { blocks.append(["type": "text", "text": text]) }
        return ChatTurn(role: .user, content: blocks)
    }
}

/// Raw HTTP to the Messages API: no SDK exists for Swift.
public enum AnthropicRequest {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    static let system = """
        Ты помощник в приложении Mely, которое живёт в челке Mac. Отвечай на языке вопроса, \
        кратко и по делу: окно небольшое. Используй Markdown, когда он помогает: списки, код. \
        Для свежих фактов, новостей и цен ищи в интернете.
        Короткий вопрос без своей темы продолжает предыдущий: «а сейчас?», «а за месяц?» — про то же, \
        о чём говорили. Mely — только место, где идёт разговор, а не его тема: не ищи и не рассказывай \
        про Mely, пока о ней не спросили прямо.
        """

    public static func body(model: ChatModel, history: [ChatTurn]) -> [String: Any] {
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 64000,
            "stream": true,
            "system": system,
            "messages": history.map { ["role": $0.role.rawValue, "content": $0.content.map(\.value)] },
            "tools": [model.webSearchTool],
        ]
        if model.supportsFallbacks { body["fallbacks"] = "default" }
        return body
    }

    public static func urlRequest(apiKey: String, model: ChatModel, history: [ChatTurn]) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if model.supportsFallbacks { request.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body(model: model, history: history))
        return request
    }
}

/// Sends a request and yields stream events. A protocol so the conversation can be tested.
public protocol ChatTransport: Sendable {
    func stream(apiKey: String, model: ChatModel, history: [ChatTurn]) -> AsyncThrowingStream<SSEEvent, Error>
    /// The conversation was cleared: forget any server-side thread.
    func reset()
}

public extension ChatTransport {
    func reset() {}
}

/// How the chat reaches Claude.
public enum ChatRoute: String, CaseIterable, Identifiable, Sendable {
    /// The user's Claude plan through the local Claude Code CLI: works without a key.
    case subscription
    /// The Anthropic API with the user's key, billed per use.
    case apiKey

    public static let `default` = ChatRoute.subscription
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .subscription: "Подписка Claude (через Claude Code)"
        case .apiKey: "Ключ Anthropic API"
        }
    }

    /// The line the chat shows, so it is clear what pays for the answer.
    public var caption: String {
        switch self {
        case .subscription: "через подписку Claude · расходует лимит плана"
        case .apiKey: "через ключ API · оплата по использованию"
        }
    }
}

public struct URLSessionChatTransport: ChatTransport {
    public init() {}

    public func stream(apiKey: String, model: ChatModel, history: [ChatTurn]) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try AnthropicRequest.urlRequest(apiKey: apiKey, model: model, history: history)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte); if body.count > 65_536 { break } }
                        throw AnthropicError(status: status, body: body)
                    }
                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        if let event = parser.flushIfNewEvent(line) { continuation.yield(event) }
                        if let event = parser.feed(line) { continuation.yield(event) }
                    }
                    if let event = parser.finish() { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
