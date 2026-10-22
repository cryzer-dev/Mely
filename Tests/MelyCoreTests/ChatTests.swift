import Testing
import Foundation
@testable import MelyCore

/// Replays fixed events and records the history each request carried.
private final class FakeTransport: ChatTransport, @unchecked Sendable {
    var replies: [[SSEEvent]]
    var error: Error?
    private(set) var requests: [[ChatTurn]] = []

    init(_ replies: [[SSEEvent]], error: Error? = nil) {
        self.replies = replies
        self.error = error
    }

    func stream(apiKey: String, model: ChatModel, history: [ChatTurn]) -> AsyncThrowingStream<SSEEvent, Error> {
        requests.append(history)
        let events = replies.isEmpty ? [] : replies.removeFirst()
        let error = self.error
        return AsyncThrowingStream { c in
            for e in events { c.yield(e) }
            c.finish(throwing: error)
        }
    }
}

/// Starts an answer and never finishes it: the chat stays streaming until cancelled.
private final class HoldingTransport: ChatTransport, @unchecked Sendable {
    private(set) var requests: [[ChatTurn]] = []
    private(set) var resets = 0

    func stream(apiKey: String, model: ChatModel, history: [ChatTurn]) -> AsyncThrowingStream<SSEEvent, Error> {
        requests.append(history)
        return AsyncThrowingStream { c in
            c.yield(ev(#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"Сейчас"}}"#))
        }
    }

    func reset() { resets += 1 }
}

private func ev(_ json: String) -> SSEEvent {
    let type = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["type"] as? String ?? ""
    return SSEEvent(event: type, data: json)
}

private let answer: [SSEEvent] = [
    ev(#"{"type":"message_start","message":{"model":"claude-opus-5-5"}}"#),
    ev(#"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#),
    ev(#"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig"}}"#),
    ev(#"{"type":"content_block_stop","index":0}"#),
    ev(#"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#),
    ev(#"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Приве"}}"#),
    ev(#"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"т!"}}"#),
    ev(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#),
    ev(#"{"type":"message_stop"}"#),
]

@Suite struct AnthropicStreamTests {
    @Test func parsesServerSentEvents() {
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for line in ["event: ping", "data: {\"type\":\"ping\"}", "", ": keep-alive", "event: message_stop", "data: {}"] {
            if let e = parser.feed(line) { events.append(e) }
        }
        if let e = parser.finish() { events.append(e) }
        #expect(events == [SSEEvent(event: "ping", data: "{\"type\":\"ping\"}"), SSEEvent(event: "message_stop", data: "{}")])

        // URLSession's lines drop blank lines: the next `event:` ends the previous event.
        var noBlanks = SSEParser()
        #expect(noBlanks.feed("event: a") == nil)
        #expect(noBlanks.feed("data: 1") == nil)
        #expect(noBlanks.flushIfNewEvent("event: b") == SSEEvent(event: "a", data: "1"))
    }

    @Test func accumulatesTextAndKeepsThinkingForHistory() {
        var acc = MessageAccumulator()
        answer.forEach { acc.apply($0) }
        #expect(acc.text == "Привет!")
        #expect(acc.model == "claude-opus-5-5")
        #expect(acc.stopReason == "end_turn")
        #expect(acc.isFinished)
        let history = acc.historyContent
        #expect(history.count == 2)
        #expect(history[0]["type"] as? String == "thinking")
        #expect(history[0]["signature"] as? String == "sig")
    }

    @Test func midStreamFallbackDropsDeclinedInternals() {
        var acc = MessageAccumulator()
        [ev(#"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":"a"}}"#),
         ev(#"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":"Нача"}}"#),
         ev(#"{"type":"content_block_start","index":2,"content_block":{"type":"fallback","from":{"model":"claude-opus-5-5"},"to":{"model":"claude-opus-5"}}}"#),
         ev(#"{"type":"content_block_start","index":3,"content_block":{"type":"thinking","thinking":"","signature":"b"}}"#),
         ev(#"{"type":"content_block_start","index":4,"content_block":{"type":"text","text":"ло."}}"#),
        ].forEach { acc.apply($0) }
        #expect(acc.text == "Начало.")
        let types = acc.historyContent.map { $0["type"] as? String }
        #expect(types == ["text", "thinking", "text"])
        #expect(acc.historyContent[1]["signature"] as? String == "b")
    }

    @Test func searchThenAnswerAcrossMessages() {
        // Claude Code with WebSearch: a short line, a search step, then the answer in a new message.
        var acc = MessageAccumulator()
        [ev(#"{"type":"message_start","message":{}}"#),
         ev(#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"Сейчас поищу."}}"#),
         ev(#"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","name":"WebSearch","id":"t"}}"#),
        ].forEach { acc.apply($0) }
        #expect(acc.isSearching)
        [ev(#"{"type":"message_start","message":{}}"#),
         ev(#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#),
         ev(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Курс — 92 ₽."}}"#),
        ].forEach { acc.apply($0) }
        #expect(!acc.isSearching)
        #expect(acc.text == "Сейчас поищу.\n\nКурс — 92 ₽.")
    }

    @Test func refusalAndErrors() {
        var acc = MessageAccumulator()
        acc.apply(ev(#"{"type":"message_delta","delta":{"stop_reason":"refusal"}}"#))
        #expect(acc.wasRefused)
        var failed = MessageAccumulator()
        failed.apply(ev(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#))
        #expect(failed.error?.errorDescription?.contains("перегружен") == true)
        let http = AnthropicError(status: 401, body: Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8))
        #expect(http.errorDescription?.contains("Ключ API") == true)
    }

    @Test func requestBodyAndHeaders() throws {
        let image = ChatAttachment(name: "shot.png", kind: .image, mediaType: "image/png", data: Data([1, 2, 3]))
        let note = ChatAttachment(name: "notes.md", kind: .text, mediaType: "text/plain", data: Data("# hi".utf8))
        let turn = ChatTurn.question("Что на скрине?", attachments: [image, note])
        let request = try AnthropicRequest.urlRequest(apiKey: "sk-test", model: .opus, history: [turn])
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["stream"] as? Bool == true)
        #expect(body["fallbacks"] as? String == "default")
        #expect(body["thinking"] == nil)  // Opus 5.5 thinks adaptively by default
        #expect((body["tools"] as? [[String: Any]])?.first?["type"] as? String == "web_search_20260209")
        let content = try #require(((body["messages"] as? [[String: Any]])?.first)?["content"] as? [[String: Any]])
        #expect(content.map { $0["type"] as? String } == ["image", "document", "text"])
        #expect((content[0]["source"] as? [String: Any])?["data"] as? String == "AQID")
        #expect((content[1]["source"] as? [String: Any])?["data"] as? String == "# hi")

        let haiku = try AnthropicRequest.urlRequest(apiKey: "k", model: .haiku, history: [turn])
        #expect(haiku.value(forHTTPHeaderField: "anthropic-beta") == nil)
        let haikuBody = try JSONSerialization.jsonObject(with: haiku.httpBody!) as? [String: Any]
        #expect(haikuBody?["fallbacks"] == nil)
    }

    @Test func loadsAttachments() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mely-chat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = dir.appendingPathComponent("a.swift"), binary = dir.appendingPathComponent("b.bin")
        try Data("let x = 1".utf8).write(to: text)
        try Data([0xFF, 0xFE, 0x00, 0xC0]).write(to: binary)
        #expect(try ChatAttachment.load(text).kind == .text)
        #expect(throws: ChatAttachment.LoadError.unsupported("b.bin")) { try ChatAttachment.load(binary) }
    }
}

@Suite struct ChatMarkdownTests {
    @Test func blocks() {
        let md = """
        ## Итог
        Корзина **считает** скидки.
        Вторая строка.

        - первый
          - вложенный
        2. второй

        > цитата
        ```swift
        let a = 1
        ```
        ---
        """
        #expect(ChatMarkdown.blocks(md) == [
            .heading(level: 2, text: "Итог"),
            .paragraph("Корзина **считает** скидки.\nВторая строка."),
            .listItem(ordered: nil, indent: 0, text: "первый"),
            .listItem(ordered: nil, indent: 1, text: "вложенный"),
            .listItem(ordered: 2, indent: 0, text: "второй"),
            .quote("цитата"),
            .code(language: "swift", text: "let a = 1"),
            .rule,
        ])
    }

    @Test func unclosedFenceWhileStreaming() {
        #expect(ChatMarkdown.blocks("Код:\n```js\nconst a") == [.paragraph("Код:"), .code(language: "js", text: "const a")])
        #expect(ChatMarkdown.blocks("#хештег") == [.paragraph("#хештег")])
    }
}

@MainActor
@Suite struct ChatConversationTests {
    @Test func answeredTurnsBuildTheHistory() async throws {
        let transport = FakeTransport([answer, answer])
        let chat = ChatConversation(transport: transport, apiKey: { "k" }, model: { .opus })
        chat.send("Привет")
        try await waitUntil { !chat.isStreaming }
        #expect(chat.messages.map(\.text) == ["Привет", "Привет!"])
        #expect(chat.messages.last?.state == .done)
        chat.send("Ещё")
        try await waitUntil { !chat.isStreaming }
        // The second request carries question, answer (with its thinking block), question.
        let second = try #require(transport.requests.last)
        #expect(second.map(\.role) == [.user, .assistant, .user])
        #expect(second[1].content.first?["type"] as? String == "thinking")
    }

    @Test func melyReactsToTheAnswerForAWhile() async throws {
        let chat = ChatConversation(transport: FakeTransport([answer]), apiKey: { "k" }, model: { .opus })
        #expect(chat.characterPose() == nil)
        chat.send("Привет")
        #expect(chat.characterPose() == .working)
        try await waitUntil { !chat.isStreaming }
        let answered = try #require(chat.answeredAt)
        #expect(chat.characterPose(now: answered.addingTimeInterval(1)) == .happy)
        #expect(chat.characterPose(now: answered.addingTimeInterval(ChatConversation.reactionTime + 1)) == nil)
    }

    @Test func refusedOrFailedTurnsStayOutOfHistory() async throws {
        let refusal = [ev(#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"Частично"}}"#),
                       ev(#"{"type":"message_delta","delta":{"stop_reason":"refusal"}}"#)]
        let transport = FakeTransport([refusal, answer])
        let chat = ChatConversation(transport: transport, apiKey: { "k" }, model: { .opus })
        chat.send("Вопрос")
        try await waitUntil { !chat.isStreaming }
        #expect(chat.messages.last?.state == .refused)
        #expect(chat.messages.last?.text == "")
        chat.send("Другой вопрос")
        try await waitUntil { !chat.isStreaming }
        #expect(transport.requests.last?.count == 1)

        let failing = FakeTransport([[]], error: AnthropicError(status: 429, type: "rate_limit_error", message: ""))
        let chat2 = ChatConversation(transport: failing, apiKey: { "k" }, model: { .opus })
        chat2.send("Вопрос")
        try await waitUntil { !chat2.isStreaming }
        guard case .failed(let message) = chat2.messages.last?.state else { Issue.record("not failed"); return }
        #expect(message.contains("Слишком много"))
    }

    @Test func windowContextGoesWithTheFirstQuestionOnly() async throws {
        let transport = FakeTransport([answer, answer])
        let chat = ChatConversation(transport: transport, apiKey: { "k" }, model: { .opus })
        chat.offer(context: ChatContext(appName: "Safari", windowTitle: "Корзина", url: "https://shop.ru/cart"))
        #expect(chat.context?.label == "Safari · shop.ru")
        chat.send("Что тут не так?")
        try await waitUntil { !chat.isStreaming }
        let first = try #require(transport.requests.first?.last)
        #expect((first.content.first?["text"] as? String)?.contains("https://shop.ru/cart") == true)
        // A running conversation keeps its context; the next question goes without it.
        chat.offer(context: ChatContext(appName: "Finder", windowTitle: "", url: nil))
        #expect(chat.context?.appName == "Safari")
        chat.send("А ещё?")
        try await waitUntil { !chat.isStreaming }
        let second = try #require(transport.requests.last?.last)
        #expect(second.content.count == 1)
        chat.clear()
        #expect(chat.context == nil)
    }

    /// «Новый разговор» (and ⌘N): an answer still coming stops, and the next question goes
    /// without the old conversation.
    @Test func newConversationStopsTheAnswerAndForgets() async throws {
        let transport = HoldingTransport()
        let chat = ChatConversation(transport: transport, apiKey: { "k" }, model: { .opus })
        chat.offer(context: ChatContext(appName: "Safari", windowTitle: "Корзина", url: nil))
        chat.send("Первый вопрос")
        try await waitUntil { chat.messages.last?.text == "Сейчас" }
        #expect(chat.isStreaming)
        chat.clear()
        #expect(chat.messages.isEmpty)
        #expect(!chat.isStreaming)
        #expect(chat.context == nil)
        #expect(transport.resets == 1)
        chat.send("Второй вопрос")
        try await waitUntil { chat.messages.last?.text == "Сейчас" }
        #expect(transport.requests.count == 2)
        let second = try #require(transport.requests.last)
        #expect(second.count == 1)
        #expect((second.first?.content.first?["text"] as? String)?.contains("Второй вопрос") == true)
        #expect(chat.messages.map(\.text) == ["Второй вопрос", "Сейчас"])
    }

    @Test func melyDroppedOnAWindowStartsAConversationAboutIt() async throws {
        let transport = FakeTransport([answer, answer])
        let chat = ChatConversation(transport: transport, apiKey: { "k" }, model: { .opus })
        chat.send("Привет")
        try await waitUntil { !chat.isStreaming }
        chat.ask(about: ChatContext(appName: "Safari", windowTitle: "Статья", url: "https://habr.com/a"))
        #expect(chat.messages.isEmpty)
        #expect(chat.context?.label == "Safari · habr.com")
        chat.send("О чём это?")
        try await waitUntil { !chat.isStreaming }
        let question = try #require(transport.requests.last)
        #expect(question.count == 1)
        #expect((question.last?.content.first?["text"] as? String)?.contains("habr.com") == true)
    }

    @Test func preferencesRouteAndHints() throws {
        let defaults = try #require(UserDefaults(suiteName: "mely-chat-\(UUID().uuidString)"))
        let prefs = ChatPreferences(defaults: defaults)
        #expect(prefs.route == .subscription)
        #expect(prefs.setupHint?.contains("Claude Code") == true)
        prefs.claudeFound = true
        #expect(prefs.setupHint == nil)
        var switched = 0
        prefs.onRouteChange = { switched += 1 }
        prefs.route = .apiKey
        prefs.route = .apiKey
        #expect(switched == 1)
        #expect(prefs.setupHint?.contains("ключ API") == true)
        prefs.model = .haiku
        #expect(ChatPreferences(defaults: defaults).model == .haiku)
        #expect(ChatPreferences(defaults: defaults).route == .apiKey)
    }

    @Test func openInClaudeDesktop() async throws {
        let chat = ChatConversation(transport: FakeTransport([answer]), apiKey: { "k" }, model: { .opus })
        chat.send("Привет")
        try await waitUntil { !chat.isStreaming }
        let prompt = ClaudeDesktopHandoff.prompt(for: chat)
        #expect(prompt.contains("Я: Привет"))
        #expect(prompt.contains("Claude: Привет!"))
        let url = try #require(ClaudeDesktopHandoff.url(for: prompt))
        #expect(url.absoluteString.hasPrefix("claude://claude.ai/new?q="))
        #expect(url.absoluteString.hasSuffix("&surface=chat&source=services"))
        let back = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
        #expect(back == prompt)
        // Too long: the end stays, cut on a character, marked.
        let long = String(repeating: "абв", count: 4000) + "КОНЕЦ"
        let tail = ClaudeDesktopHandoff.tail(long)
        #expect(tail.utf8.count <= ClaudeDesktopHandoff.maxBytes)
        #expect(tail.hasPrefix("…") && tail.hasSuffix("КОНЕЦ"))
    }

    @Test func noKeyNoRequest() {
        let transport = FakeTransport([answer])
        let chat = ChatConversation(transport: transport, apiKey: { nil }, model: { .opus })
        #expect(!chat.isReady)
        #expect(chat.setupHint?.contains("ключ API") == true)
        chat.send("Привет")
        #expect(chat.messages.isEmpty)
        #expect(transport.requests.isEmpty)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }
}

@Suite struct ClaudeCodeChatTransportTests {
    /// Lines as `claude -p --output-format stream-json --include-partial-messages` prints them.
    static let output = [
        #"{"type":"system","subtype":"init","session_id":"s-1","model":"claude-opus-5-5"}"#,
        #"{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-opus-5-5"}}}"#,
        #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}"#,
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Прив"}}}"#,
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ет!"}}}"#,
        #"{"type":"assistant","message":{}}"#,
        #"{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"}}}"#,
        #"{"type":"stream_event","event":{"type":"message_stop"}}"#,
        #"{"type":"result","subtype":"success","is_error":false,"result":"Привет!","session_id":"s-1"}"#,
    ]

    @Test func parsesLines() {
        #expect(ClaudeCodeChatTransport.parse(Self.output[0]) == .session("s-1"))
        guard case .event(let e) = ClaudeCodeChatTransport.parse(Self.output[3]) else { Issue.record("no event"); return }
        #expect(e.event == "content_block_delta")
        #expect(ClaudeCodeChatTransport.parse(Self.output[5]) == .other)
        #expect(ClaudeCodeChatTransport.parse(Self.output[8]) == .done)
        #expect(ClaudeCodeChatTransport.parse(#"{"type":"result","is_error":true,"result":"Not logged in · Please run /login"}"#)
                == .failed("Not logged in · Please run /login"))
        #expect(ClaudeCodeChatError(output: "Not logged in · Please run /login").errorDescription?.contains("/login") == true)
    }

    @Test func argumentsKeepItToTalking() {
        let t = ClaudeCodeChatTransport(executable: URL(fileURLWithPath: "/bin/echo"))
        let first = t.arguments(model: .sonnet, resume: nil)
        #expect(first.contains("--restricted"))
        #expect(first[first.firstIndex(of: "--tools")! + 1] == "WebSearch")
        #expect(first[first.firstIndex(of: "--allowedTools")! + 1] == "WebSearch")
        #expect(first[first.firstIndex(of: "--model")! + 1] == "claude-sonnet-5-5")
        #expect(!first.contains("--resume"))
        #expect(t.arguments(model: .opus, resume: "s-1").suffix(2) == ["--resume", "s-1"])
        let line = String(decoding: ClaudeCodeChatTransport.inputLine(.question("hi", attachments: [])), as: UTF8.self)
        #expect(line.hasPrefix(#"{"#) && line.hasSuffix("\n"))
        #expect(line.contains(#""type":"user""#))
    }

    /// The whole pipe through a stand-in `claude` that prints the recorded stream.
    @Test func streamsThroughAProcessAndResumes() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mely-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("claude")
        let args = dir.appendingPathComponent("args.txt")
        let body = Self.output.map { "echo '\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: "\n")
        // One line per call: the system prompt has line breaks of its own.
        try "#!/bin/sh\ncat > /dev/null\nprintf '%s' \"$*\" | tr '\\n' ' ' >> '\(args.path)'\necho >> '\(args.path)'\n\(body)\n"
            .write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let transport = ClaudeCodeChatTransport(executable: fake, workdir: dir.appendingPathComponent("work"))
        var acc = MessageAccumulator()
        for try await event in transport.stream(apiKey: "", model: .opus, history: [.question("Привет", attachments: [])]) {
            acc.apply(event)
        }
        #expect(acc.text == "Привет!")
        // The second question continues the same Claude Code session.
        let history: [ChatTurn] = [.question("a", attachments: []), ChatTurn(role: .assistant, content: []),
                                   .question("b", attachments: [])]
        for try await _ in transport.stream(apiKey: "", model: .opus, history: history) {}
        let calls = try String(contentsOf: args, encoding: .utf8).split(separator: "\n")
        #expect(calls.count == 2)
        #expect(!calls[0].contains("--resume"))
        #expect(calls[1].hasSuffix("--resume s-1"))
        transport.reset()
        for try await _ in transport.stream(apiKey: "", model: .opus, history: history) {}
        let after = try String(contentsOf: args, encoding: .utf8).split(separator: "\n")
        #expect(!after[2].contains("--resume"))
    }

    /// A stand-in `claude`: reads the question, then runs `script`.
    static func fake(_ script: String) throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mely-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fake = dir.appendingPathComponent("claude")
        try "#!/bin/sh\ncat > /dev/null\n\(script)\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        return (dir, fake)
    }

    static var answer: String {
        output.map { "echo '\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: "\n")
    }

    /// The chat stalled for good while the Now Playing adapter waited on its pipe.
    @Test func answersWhileAnotherPipeIsQuiet() async throws {
        let quiet = Process()
        quiet.executableURL = URL(fileURLWithPath: "/bin/sleep")
        quiet.arguments = ["30"]
        let pipe = Pipe()
        quiet.standardOutput = pipe
        try quiet.run()
        defer { quiet.terminate() }
        // The old way of reading, which held every other `bytes` reader back.
        let reader = Task.detached { for try await _ in pipe.fileHandleForReading.bytes.lines {} }
        defer { reader.cancel() }

        let (dir, fake) = try Self.fake(Self.answer)
        defer { try? FileManager.default.removeItem(at: dir) }
        let transport = ClaudeCodeChatTransport(executable: fake, workdir: dir.appendingPathComponent("work"))
        var acc = MessageAccumulator()
        for try await event in transport.stream(apiKey: "", model: .opus, history: [.question("Привет", attachments: [])]) {
            acc.apply(event)
        }
        #expect(acc.text == "Привет!")
    }

    /// 200 KB of warnings, and the process lingers after its result with stdout open.
    @Test func noisyStderrAndALingeringProcess() async throws {
        let (dir, fake) = try Self.fake("head -c 204800 /dev/zero | tr '\\0' 'w' >&2\n\(Self.answer)\nsleep 30")
        defer { try? FileManager.default.removeItem(at: dir) }
        let transport = ClaudeCodeChatTransport(executable: fake, workdir: dir.appendingPathComponent("work"))
        let start = Date()
        var acc = MessageAccumulator()
        for try await event in transport.stream(apiKey: "", model: .opus, history: [.question("Привет", attachments: [])]) {
            acc.apply(event)
        }
        #expect(acc.text == "Привет!")
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test func silenceEndsWithAnError() async throws {
        let (dir, fake) = try Self.fake("sleep 30")
        defer { try? FileManager.default.removeItem(at: dir) }
        let transport = ClaudeCodeChatTransport(executable: fake, workdir: dir.appendingPathComponent("work"))
        transport.silenceLimit = 1
        await #expect(throws: ClaudeCodeChatError.silent) {
            for try await _ in transport.stream(apiKey: "", model: .opus, history: [.question("Привет", attachments: [])]) {}
        }
    }

    @Test func failureShowsTheLastOfStderr() async throws {
        let (dir, fake) = try Self.fake("echo 'env: node: No such file or directory' >&2\nexit 127")
        defer { try? FileManager.default.removeItem(at: dir) }
        let transport = ClaudeCodeChatTransport(executable: fake, workdir: dir.appendingPathComponent("work"))
        await #expect(throws: ClaudeCodeChatError(output: "env: node: No such file or directory\n")) {
            for try await _ in transport.stream(apiKey: "", model: .opus, history: [.question("Привет", attachments: [])]) {}
        }
        #expect(ClaudeCodeChatTransport.environment(for: fake)["PATH"]?.hasPrefix(dir.path + ":") == true)
    }
}

@Suite struct PipeLinesTests {
    @Test func splitsChunksIntoLines() {
        let buffer = LineBuffer()
        #expect(buffer.append(Data("a\r\nb".utf8)) == ["a"])
        #expect(buffer.append(Data("c\n\nd".utf8)) == ["bc", ""])
        #expect(buffer.flush() == "d")
        #expect(buffer.flush() == nil)
    }
}

@Suite struct ClaudeLocateTests {
    /// A fake home with `claude` at `relative`.
    func home(with relative: String) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("mely-home-\(UUID().uuidString)")
        let file = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        return home
    }

    @Test func findsTheNewestNvmNode() throws {
        let home = try home(with: ".nvm/versions/node/v22.11.0/bin/claude")
        _ = try self.home(with: "x") // unrelated
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".nvm/versions/node/v9.0.0/bin"),
                                                withIntermediateDirectories: true)
        let list = ClaudeCodeChatTransport.candidates(home: home).filter { $0.contains(".nvm") }
        #expect(list.first?.contains("v22.11.0") == true)
    }

    @Test func findsTheCopyInsideClaudeDesktop() throws {
        let home = try home(with: "Library/Application Support/Claude/claude-code/2.1.304/abc/claude.app/Contents/MacOS/claude")
        let found = ClaudeCodeChatTransport.locate(home: home, askShell: false)
        // Homebrew or /usr/local on this Mac win; otherwise the Desktop copy is used.
        #expect(found != nil)
        #expect(ClaudeCodeChatTransport.candidates(home: home).contains { $0.hasSuffix("abc/claude.app/Contents/MacOS/claude") })
    }

    @Test func findsVoltaAndBun() throws {
        for path in [".volta/bin/claude", ".bun/bin/claude"] {
            let home = try home(with: path)
            #expect(ClaudeCodeChatTransport.candidates(home: home).contains(home.appendingPathComponent(path).path))
        }
    }
}
