import AppKit
import SwiftUI
import Observation
import MelyCore
import MelyUI

/// Claude Code: the relay at ~/.mely/bin/nc-hook and the hooks in ~/.claude/settings.json
/// (written only after the user confirms the diff); events come through `AgentHookHub`.
@MainActor
@Observable
final class ClaudeCodeIntegration: Integration {
    let id = "claude-code"
    let displayName = "Claude Code"
    let summary = "Сессии из терминала и JetBrains IDE, разрешения, вопросы, лимиты"
    private(set) var status: IntegrationStatus = .off

    @ObservationIgnored private let setup = ClaudeCodeSetup()
    @ObservationIgnored private let hub: AgentHookHub
    @ObservationIgnored private var changeWindow: NSWindow?

    init(hub: AgentHookHub) {
        self.hub = hub
    }

    var actions: [IntegrationAction] {
        guard status != .off else { return [] }
        if setup.hooksInstalled() {
            return [IntegrationAction(id: "uninstall", title: "Отключить hooks", isDestructive: true) { [weak self] in
                self?.presentUninstall()
            }]
        }
        let title = setup.onlyStatusLineMissing() ? "Обновить…" : "Подключить…"
        return [IntegrationAction(id: "install", title: title) { [weak self] in self?.presentInstall() }]
    }

    func start() async {
        // build-app.sh puts the relay in Contents/Helpers; copy it to a path without spaces.
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/nc-hook")
        if FileManager.default.fileExists(atPath: bundled.path) {
            try? setup.installRelay(from: bundled)
        }
        do {
            try hub.open(for: .claude)
        } catch {
            status = .error("Не удалось открыть сокет: \(error.localizedDescription)")
            return
        }
        refreshStatus()
        if !setup.hooksInstalled() { presentInstall() }
    }

    func stop() async {
        hub.close(for: .claude)
        status = .off
    }

    private func refreshStatus() {
        if setup.hooksInstalled() {
            status = .running
        } else if setup.onlyStatusLineMissing() {
            status = .needsSetup("Нужно обновить: лимиты плана берутся из statusLine")
        } else {
            status = .needsSetup("Не подключено: hooks не установлены")
        }
    }

    // MARK: - Confirm window

    private func presentInstall() {
        present(prepare: { [setup] in try setup.prepareInstall() })
    }

    private func presentUninstall() {
        present(prepare: { [setup] in try setup.prepareUninstall() })
    }

    private func present(prepare: @escaping () throws -> PendingSettingsChange) {
        changeWindow?.close()
        let host = ChangeHost(prepare: prepare,
                              apply: { [setup] change in try setup.apply(change) },
                              finish: { [weak self] in
                                  self?.changeWindow?.close()
                                  self?.changeWindow = nil
                                  self?.refreshStatus()
                              })
        let window = NSWindow(contentViewController: NSHostingController(rootView: host))
        window.title = "Mely — изменение настроек Claude Code"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        changeWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Builds the change and applies it.
private struct ChangeHost: View {
    let prepare: () throws -> PendingSettingsChange
    let apply: (PendingSettingsChange) throws -> URL?
    let finish: () -> Void
    @State private var error: String?

    var body: some View {
        switch Result(catching: { try prepare() }) {
        case .success(let change):
            SettingsChangeView(change: change, error: error,
                               onApply: {
                                   do { _ = try apply(change); finish() }
                                   catch { self.error = error.localizedDescription }
                               },
                               onCancel: finish)
        case .failure(let failure):
            VStack(spacing: 12) {
                Label(failure.localizedDescription, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Button("Закрыть", action: finish)
            }
            .padding(24)
            .frame(width: 480)
        }
    }
}
