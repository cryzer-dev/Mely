import AppKit
import SwiftUI
import Observation
import OSLog
import MelyCore
import MelyUI

private let log = Logger(subsystem: "dev.mely.app", category: "codex")

/// Codex CLI: Mely's hooks in ~/.codex/hooks.json with Codex's approval of them in
/// ~/.codex/config.toml, both written only after the user confirms the diff. Events come
/// through `AgentHookHub`, like Claude Code's.
@MainActor
@Observable
final class CodexIntegration: Integration {
    let id = "codex"
    let displayName = "Codex"
    let summary = "Сессии Codex CLI, его разрешения и лимиты плана ChatGPT"
    private(set) var status: IntegrationStatus = .off

    @ObservationIgnored private let setup = CodexSetup()
    @ObservationIgnored private let hub: AgentHookHub
    @ObservationIgnored private var changeWindow: NSWindow?
    /// The `codex` command; nil while it is not installed.
    @ObservationIgnored private(set) var codex: URL?
    /// Codex's plan limits, asked of its app server while they are on screen.
    let usage = PlanUsageStore(agent: .codex)
    /// Where Codex's limits show right now; the app knows (the island, the pin).
    @ObservationIgnored var limitsVisibility: () -> CodexUsagePoll.Visibility = { .hidden }
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var lastAsked: Date?
    @ObservationIgnored private var asking = false

    init(hub: AgentHookHub) {
        self.hub = hub
    }

    var actions: [IntegrationAction] {
        guard status != .off else { return [] }
        guard codex != nil else {
            return [IntegrationAction(id: "find", title: "Проверить снова") { [weak self] in
                Task { await self?.refresh(offerInstall: true) }
            }]
        }
        switch setup.state() {
        case .installed:
            return [IntegrationAction(id: "uninstall", title: "Отключить hooks", isDestructive: true) { [weak self] in
                self?.present(install: false)
            }]
        case .changed:
            return [IntegrationAction(id: "install", title: "Поставить заново…") { [weak self] in self?.present(install: true) }]
        case .notInstalled:
            return [IntegrationAction(id: "install", title: "Подключить…") { [weak self] in self?.present(install: true) }]
        }
    }

    func start() async {
        // The same relay as Claude Code's, in case Claude Code is off.
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/nc-hook")
        if FileManager.default.fileExists(atPath: bundled.path) {
            try? ClaudeCodeSetup().installRelay(from: bundled)
        }
        do {
            try hub.open(for: .codex)
        } catch {
            status = .error("Не удалось открыть сокет: \(error.localizedDescription)")
            return
        }
        await refresh(offerInstall: true)
        startPolling()
    }

    func stop() async {
        pollTimer?.invalidate()
        pollTimer = nil
        hub.close(for: .codex)
        changeWindow?.close()
        changeWindow = nil
        status = .off
    }

    /// Finds Codex, reads the files, asks Codex whether it trusts Mely's hooks.
    private func refresh(offerInstall: Bool) async {
        codex = CodexAppServer.locate()
        guard let codex else {
            status = .needsSetup("Codex не найден: поставь его командой npm i -g @openai/codex")
            return
        }
        switch setup.state() {
        case .notInstalled:
            status = .needsSetup("Не подключено: hooks не установлены")
            if offerInstall { present(install: true) }
        case .changed:
            status = .needsSetup("Изменены вручную: поставь hooks заново")
        case .installed:
            // The files say yes; Codex has the last word (an approval taken back in /hooks).
            let statuses = (try? await setup.trustStatuses(codex: codex)) ?? []
            if !statuses.isEmpty, statuses.contains(where: { $0 != "trusted" }) {
                log.info("codex hooks not trusted: \(Set(statuses).sorted().joined(separator: ","), privacy: .public)")
                status = .needsSetup("Изменены вручную: Codex не доверяет hooks Mely, поставь их заново")
            } else {
                status = .running
            }
        }
    }

    // MARK: - Limits

    /// Checks every 15 s whether the limits are due (`CodexUsagePoll`): hidden, Codex is
    /// never started for them.
    private func startPolling() {
        guard pollTimer == nil else { return }
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollIfDue() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
        pollIfDue()
    }

    /// Asks now if the limits are on screen and due; also right when they come on screen.
    func pollIfDue() {
        guard status != .off, !asking, let codex,
              CodexUsagePoll.isDue(last: lastAsked, now: Date(), visibility: limitsVisibility()) else { return }
        asking = true
        lastAsked = Date()
        log.info("asking codex for limits")
        Task { [weak self] in
            do {
                let read = try await CodexUsage.read(codex: codex)
                if let read { self?.usage.set(read) } else { self?.usage.problem = "Нет данных: Codex не прислал лимиты" }
            } catch {
                self?.usage.problem = CodexUsage.problem(for: error)
            }
            self?.asking = false
        }
    }

    // MARK: - Confirm window

    private func present(install: Bool) {
        changeWindow?.close()
        let setup = setup, codex = codex
        let view = CodexChangeHost(
            prepare: {
                if install {
                    guard let codex else { throw CodexAppServer.Failure.notFound }
                    return try await setup.prepareInstall { try await setup.hashes(for: $0, codex: codex) }
                }
                return try setup.prepareUninstall()
            },
            apply: { try setup.apply($0) },
            finish: { [weak self] in
                self?.changeWindow?.close()
                self?.changeWindow = nil
                Task { await self?.refresh(offerInstall: false) }
            })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Mely — изменение настроек Codex"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        changeWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Builds the change (asking Codex for its hashes takes a moment) and applies it.
private struct CodexChangeHost: View {
    let prepare: () async throws -> PendingSettingsChange
    let apply: (PendingSettingsChange) throws -> Void
    let finish: () -> Void
    @State private var change: Result<PendingSettingsChange, Error>?
    @State private var error: String?

    var body: some View {
        Group {
            switch change {
            case nil:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Спрашиваю Codex…").foregroundStyle(.secondary)
                }
                .frame(width: 620, height: 520)
            case .success(let change)?:
                SettingsChangeView(change: change, error: error,
                                   onApply: {
                                       do { try apply(change); finish() }
                                       catch { self.error = error.localizedDescription }
                                   },
                                   onCancel: finish)
            case .failure(let failure)?:
                VStack(spacing: 12) {
                    Label(failure.localizedDescription, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Button("Закрыть", action: finish)
                }
                .padding(24)
                .frame(width: 480)
            }
        }
        .task {
            do { change = .success(try await prepare()) }
            catch { change = .failure(error) }
        }
    }
}
