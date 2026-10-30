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
                                       enabledByDefault: ["claude-code", "codex", "notifications", "calendar"])
    registry.register(SampleIntegration("claude-code", "Claude Code", "Сессии, разрешения, вопросы, лимиты", .running))
    registry.register(SampleIntegration("notifications", "Уведомления", "Telegram, Телемост, браузеры",
                                        .needsPermission(.fullDiskAccess)))
    registry.register(SampleIntegration("calendar", "Календарь", "События на сегодня и новые встречи",
                                        .error("Не удалось прочитать календари")))
    registry.register(SampleIntegration("now-playing", "Что играет", "Яндекс Музыка, браузер, Apple Music", .off))
    registry.register(SampleIntegration("codex", "Codex", "Сессии Codex CLI, его разрешения и лимиты плана ChatGPT",
                                        .needsSetup("Не подключено: hooks не установлены")))
    registry.showExperimental = true
    return registry
}
