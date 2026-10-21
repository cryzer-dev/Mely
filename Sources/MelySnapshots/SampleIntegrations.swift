import Foundation
import MelyCore

/// Stand-ins with fixed statuses for snapshots.
@MainActor
final class SampleIntegration: Integration {
    let id: String
    let displayName: String
    let summary: String
    let isExperimental: Bool
    let status: IntegrationStatus

    init(_ id: String, _ name: String, _ summary: String, _ status: IntegrationStatus, experimental: Bool = false) {
        self.id = id
        self.displayName = name
        self.summary = summary
        self.status = status
        self.isExperimental = experimental
    }

    func start() async {}
    func stop() async {}
}

@MainActor
func sampleRegistry() -> IntegrationRegistry {
    let defaults = UserDefaults(suiteName: "mely.snapshots")!
    defaults.removePersistentDomain(forName: "mely.snapshots")
    let registry = IntegrationRegistry(defaults: defaults,
                                       enabledByDefault: ["claude-code", "notifications", "calendar"])
    registry.register(SampleIntegration("claude-code", "Claude Code", "Сессии, разрешения, вопросы, лимиты", .running))
    registry.register(SampleIntegration("notifications", "Уведомления", "Telegram, Телемост, браузеры",
                                        .needsPermission(.fullDiskAccess)))
    registry.register(SampleIntegration("calendar", "Календарь", "События на сегодня и новые встречи",
                                        .error("Не удалось прочитать календари")))
    registry.register(SampleIntegration("now-playing", "Что играет", "Яндекс Музыка, браузер, Apple Music", .off))
    registry.register(SampleIntegration("codex", "Codex", "Сессии Codex CLI", .off, experimental: true))
    registry.showExperimental = true
    return registry
}

/// A responder nobody listens to, for cards in snapshots.
enum SampleResponder {
    static func make() -> HookResponder {
        var fds: [Int32] = [0, 0]
        socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        return HookResponder(fd: fds[0])
    }
}

/// Answers every question with the same Markdown, as a stream would.
struct SampleChatTransport: ChatTransport {
    static let answer = """
        Скорее всего, скидка считается **до** округления. Поправить можно так:

        1. Округлять цену позиции в `CartItem.total`
        2. Скидку применять к сумме корзины

        ```ts
        const total = round(items.reduce((s, i) => s + i.total, 0) * (1 - discount))
        ```
        """

    func stream(apiKey: String, model: ChatModel, history: [ChatTurn]) -> AsyncThrowingStream<SSEEvent, Error> {
        func event(_ obj: [String: Any]) -> SSEEvent {
            SSEEvent(event: obj["type"] as? String ?? "",
                     data: String(decoding: try! JSONSerialization.data(withJSONObject: obj), as: UTF8.self))
        }
        return AsyncThrowingStream { c in
            c.yield(event(["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": Self.answer]]))
            c.yield(event(["type": "message_delta", "delta": ["stop_reason": "end_turn"]]))
            c.yield(event(["type": "message_stop"]))
            c.finish()
        }
    }
}
