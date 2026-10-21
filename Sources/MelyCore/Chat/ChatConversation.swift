import Foundation
import os
import Observation

private let log = Logger(subsystem: "dev.mely.app", category: "chat")

/// A message as the chat shows it.
public struct ChatMessage: Identifiable, Equatable, Sendable {
    public enum Role: Equatable, Sendable { case user, assistant }
    public enum State: Equatable, Sendable {
        case streaming
        case done
        /// Claude declined (a safety classifier or the model itself).
        case refused
        case failed(String)
        case cancelled
    }

    public let id: UUID
    public let role: Role
    public var text: String
    /// File names attached to a question.
    public var attachments: [String]
    public var state: State
    /// Claude is searching the web for this answer.
    public var isSearching = false

    init(role: Role, text: String, attachments: [String] = [], state: State) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.attachments = attachments
        self.state = state
    }
}

/// The chat: what is shown, and the API history behind it. Only answered turns enter
/// the history, so a failed or refused question can simply be asked again.
@MainActor
@Observable
public final class ChatConversation {
    public private(set) var messages: [ChatMessage] = []
    /// Files waiting for the next question (dropped on the notch or picked).
    public private(set) var pending: [ChatAttachment] = []
    /// Why a dropped file was not attached.
    public var attachmentError: String?
    /// The window the chat was opened from; goes with the first question.
    public private(set) var context: ChatContext?
    public var isStreaming: Bool { messages.last?.state == .streaming }

    /// When the last answer ended (done, failed or declined).
    public private(set) var answeredAt: Date?
    /// How long Mely shows its reaction to an answer.
    public static let reactionTime: TimeInterval = 8

    /// How Mely reacts to the conversation while the chat is on screen: busy while Claude
    /// answers, glad or startled for a few seconds after; nil otherwise (task 6.12).
    public func characterPose(now: Date = Date()) -> CharacterPose? {
        guard let last = messages.last else { return nil }
        if last.state == .streaming { return last.isSearching ? .curious : .working }
        guard let answeredAt, now.timeIntervalSince(answeredAt) < Self.reactionTime else { return nil }
        switch last.state {
        case .failed, .refused: return .scared
        case .done where last.role == .assistant: return .happy
        default: return nil
        }
    }

    @ObservationIgnored private var history: [ChatTurn] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let transport: ChatTransport
    @ObservationIgnored private let apiKey: () -> String?
    @ObservationIgnored private let model: () -> ChatModel
    @ObservationIgnored private let setupHintSource: () -> String?
    @ObservationIgnored private let captionSource: () -> String?

    /// - Parameters:
    ///   - apiKey: the credential the transport needs; any non-empty value for a
    ///     transport that needs none.
    ///   - setupHint: why the chat cannot ask yet ("add a key", "install Claude Code").
    ///   - caption: what pays for the answers, shown above the field.
    public init(transport: ChatTransport = URLSessionChatTransport(),
                apiKey: @escaping () -> String?, model: @escaping () -> ChatModel,
                setupHint: @escaping () -> String? = { nil }, caption: @escaping () -> String? = { nil }) {
        self.transport = transport
        self.apiKey = apiKey
        self.model = model
        self.setupHintSource = setupHint
        self.captionSource = caption
    }

    /// Nil when the chat can ask; otherwise what to set up first.
    public var setupHint: String? {
        if let hint = setupHintSource() { return hint }
        return (apiKey() ?? "").isEmpty ? "Чтобы спрашивать Claude, добавьте ключ API" : nil
    }

    public var isReady: Bool { setupHint == nil }
    public var caption: String? { captionSource() }

    public func attach(_ urls: [URL]) {
        attachmentError = nil
        for url in urls {
            do { pending.append(try ChatAttachment.load(url)) }
            catch { attachmentError = error.localizedDescription }
        }
    }

    public func removeAttachment(_ id: UUID) { pending.removeAll { $0.id == id } }

    /// Set when the chat opens on a new conversation; a running one keeps its own.
    public func offer(context: ChatContext?) {
        guard history.isEmpty, !isStreaming else { return }
        self.context = context
    }

    /// Mely dropped on a window: a new conversation about it. One still answering keeps going.
    public func ask(about context: ChatContext) {
        guard !isStreaming else { return }
        if !history.isEmpty || !messages.isEmpty { clear() }
        self.context = context
    }

    public func dismissContext() { context = nil }

    /// Sends a question with the pending files. Ignored while an answer streams.
    public func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isStreaming, !text.isEmpty || !pending.isEmpty, isReady, let key = apiKey() else { return }
        let files = pending
        pending = []
        attachmentError = nil
        var question = ChatTurn.question(text.isEmpty ? "Что здесь?" : text, attachments: files)
        if history.isEmpty, let context {
            question = ChatTurn(role: .user, content: [["type": "text", "text": context.prompt]] + question.content.map(\.value))
        }
        messages.append(ChatMessage(role: .user, text: text, attachments: files.map(\.name), state: .done))
        messages.append(ChatMessage(role: .assistant, text: "", state: .streaming))
        let turns = history + [question]
        let stream = transport.stream(apiKey: key, model: model(), history: turns)
        log.info("chat send: turns=\(turns.count)")
        task = Task { [weak self] in
            var accumulator = MessageAccumulator()
            var events = 0
            do {
                for try await event in stream {
                    events += 1
                    if events == 1 { log.info("chat first event, conversation alive=\(self != nil)") }
                    accumulator.apply(event)
                    self?.updateLast {
                        $0.text = accumulator.text
                        $0.isSearching = accumulator.isSearching
                    }
                }
                log.info("chat stream ended: events=\(events), alive=\(self != nil), cancelled=\(Task.isCancelled)")
                try Task.checkCancellation()
                self?.finish(accumulator, question: question)
            } catch is CancellationError {
                log.info("chat cancelled")
                self?.updateLast { $0.state = .cancelled }
            } catch {
                log.error("chat failed: \(error.localizedDescription, privacy: .public)")
                self?.answeredAt = Date()
                self?.updateLast { $0.state = .failed(error.localizedDescription) }
            }
        }
    }

    public func cancel() {
        if task != nil { log.info("chat cancel() while streaming=\(self.isStreaming)") }
        task?.cancel()
        task = nil
        if isStreaming { updateLast { $0.state = .cancelled } }
    }

    public func clear() {
        cancel()
        transport.reset()
        messages = []
        history = []
        pending = []
        attachmentError = nil
        context = nil
    }

    private func finish(_ result: MessageAccumulator, question: ChatTurn) {
        answeredAt = Date()
        updateLast { $0.isSearching = false }
        if let error = result.error {
            updateLast { $0.state = .failed(error.localizedDescription) }
        } else if result.wasRefused {
            // A partial answer before a decline is not an answer: drop it.
            updateLast { $0.text = ""; $0.state = .refused }
        } else {
            history.append(question)
            history.append(ChatTurn(role: .assistant, content: result.historyContent))
            updateLast {
                $0.state = .done
                if result.stopReason == "max_tokens" { $0.text += "\n\n_…ответ оборван: слишком длинный._" }
            }
        }
    }

    private func updateLast(_ change: (inout ChatMessage) -> Void) {
        guard !messages.isEmpty else { return }
        change(&messages[messages.count - 1])
    }
}
