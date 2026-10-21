import Testing
import Foundation
@testable import MelyCore

@MainActor
final class FakeIntegration: Integration {
    let id: String
    let displayName: String
    let summary = ""
    let isExperimental: Bool
    var status: IntegrationStatus = .off
    var starts = 0
    var stops = 0

    init(id: String, experimental: Bool = false) {
        self.id = id
        self.displayName = id
        self.isExperimental = experimental
    }

    func start() async { starts += 1; status = .running }
    func stop() async { stops += 1; status = .off }
}

@MainActor
@Suite struct IntegrationRegistryTests {
    private func freshDefaults() -> UserDefaults {
        let name = "mely.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func onlyClaudeCodeOnAtFirstLaunch() async {
        let registry = IntegrationRegistry(defaults: freshDefaults())
        let claude = FakeIntegration(id: "claude-code")
        let music = FakeIntegration(id: "now-playing")
        registry.register(claude)
        registry.register(music)
        await registry.startEnabled()
        #expect(registry.isEnabled("claude-code") && !registry.isEnabled("now-playing"))
        #expect(claude.starts == 1 && music.starts == 0)
    }

    @Test func newDefaultIntegrationTurnsOnAfterAnUpdate() async {
        let defaults = freshDefaults()
        // The previous version knew only Claude Code, and the user switched the chat on.
        let before = IntegrationRegistry(defaults: defaults, enabledByDefault: ["claude-code"])
        before.register(FakeIntegration(id: "claude-code"))
        before.register(FakeIntegration(id: "claude-chat"))
        await before.setEnabled("claude-chat", true)
        // The update adds Now Playing, on by default.
        let after = IntegrationRegistry(defaults: defaults, enabledByDefault: ["claude-code", "now-playing"])
        after.register(FakeIntegration(id: "claude-code"))
        after.register(FakeIntegration(id: "claude-chat"))
        after.register(FakeIntegration(id: "now-playing"))
        #expect(after.isEnabled("now-playing") && after.isEnabled("claude-chat"))
        // Switched off by the user, it stays off on the next launch.
        await after.setEnabled("now-playing", false)
        let again = IntegrationRegistry(defaults: defaults, enabledByDefault: ["claude-code", "now-playing"])
        again.register(FakeIntegration(id: "now-playing"))
        #expect(!again.isEnabled("now-playing"))
    }

    @Test func switchSurvivesRestart() async {
        let defaults = freshDefaults()
        let first = IntegrationRegistry(defaults: defaults)
        let music = FakeIntegration(id: "now-playing")
        first.register(music)
        await first.setEnabled("now-playing", true)
        #expect(music.starts == 1)
        await first.setEnabled("claude-code", false)

        let second = IntegrationRegistry(defaults: defaults)
        #expect(second.isEnabled("now-playing"))
        #expect(!second.isEnabled("claude-code"))
    }

    @Test func turningOffStopsIt() async {
        let registry = IntegrationRegistry(defaults: freshDefaults())
        let music = FakeIntegration(id: "now-playing")
        registry.register(music)
        await registry.setEnabled("now-playing", true)
        await registry.setEnabled("now-playing", false)
        #expect(music.stops == 1 && music.status == .off)
    }

    @Test func experimentalHiddenUntilAsked() {
        let registry = IntegrationRegistry(defaults: freshDefaults())
        registry.register(FakeIntegration(id: "claude-code"))
        registry.register(FakeIntegration(id: "codex", experimental: true))
        #expect(registry.visible.map(\.id) == ["claude-code"])
        registry.showExperimental = true
        #expect(registry.visible.map(\.id) == ["claude-code", "codex"])
    }
}

@MainActor
final class FakePermissions: PermissionChecking {
    var granted: Set<SystemPermission> = []
    var revision = 0
    var requested: [SystemPermission] = []
    var watched: Set<SystemPermission> = []

    func isGranted(_ permission: SystemPermission) -> Bool { granted.contains(permission) }
    func watch(_ permissions: Set<SystemPermission>) { watched = permissions }
    func request(_ permission: SystemPermission) async { requested.append(permission) }
}

@MainActor
final class NeedsDiskIntegration: Integration {
    let id = "notifications"
    let displayName = "Уведомления"
    let summary = ""
    var status: IntegrationStatus = .off
    var requiredPermissions: [SystemPermission] { [.fullDiskAccess] }
    func start() async { status = .running }
    func stop() async { status = .off }
}

@MainActor
@Suite struct IntegrationPermissionTests {
    private func registry() -> (IntegrationRegistry, FakePermissions, NeedsDiskIntegration) {
        let name = "mely.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let r = IntegrationRegistry(defaults: defaults)
        let p = FakePermissions()
        let i = NeedsDiskIntegration()
        r.permissions = p
        r.register(i)
        return (r, p, i)
    }

    @Test func enablingAsksForMissingPermission() async {
        let (r, p, i) = registry()
        await r.setEnabled(i.id, true)
        #expect(p.requested == [.fullDiskAccess])
        #expect(r.status(of: i) == .needsPermission(.fullDiskAccess))
        #expect(p.watched == [.fullDiskAccess])
    }

    @Test func revokedAccessShowsWithoutRestart() async {
        let (r, p, i) = registry()
        p.granted = [.fullDiskAccess]
        await r.setEnabled(i.id, true)
        #expect(p.requested.isEmpty)
        #expect(r.status(of: i) == .running)
        p.granted = []
        p.revision += 1
        #expect(r.status(of: i) == .needsPermission(.fullDiskAccess))
    }

    @Test func switchedOffIsOffAndUnwatched() async {
        let (r, p, i) = registry()
        await r.setEnabled(i.id, true)
        await r.setEnabled(i.id, false)
        #expect(r.status(of: i) == .off)
        #expect(p.watched.isEmpty)
    }
}
