import AppKit
import os
import SwiftUI
import Observation
import MelyCore
import MelyUI

private let log = Logger(subsystem: "dev.mely.app", category: "chat")

/// Chat with Claude: through the user's Claude plan (local Claude Code, no key) or by an
/// API key in the Keychain. Off, it holds no conversation.
@MainActor
@Observable
final class ClaudeChatIntegration: Integration {
    let id = "claude-chat"
    let displayName = "Чат с Claude"
    let summary = "Вопросы Claude из челки по подписке или ключу API, файлы перетаскиванием"
    private(set) var status: IntegrationStatus = .off
    /// Exists while the integration is on.
    private(set) var conversation: ChatConversation?

    @ObservationIgnored private let keychain = KeychainStore.anthropicKey
    @ObservationIgnored private var settingsWindow: NSWindow?
    /// Read once per change, not on every view update. Observed: the chat's setup hint
    /// goes away as soon as a key is saved or the route changes.
    private var cachedKey: String?
    private(set) var claudeCLI: URL?
    /// Route and model, also changed from the chat's model pill.
    let preferences = ChatPreferences()
    @ObservationIgnored private var cliTransport: ClaudeCodeChatTransport?
    /// While Claude Code is missing, looks again every minute: it may be installed later.
    @ObservationIgnored private var searchAgain: Task<Void, Never>?

    var actions: [IntegrationAction] {
        guard status != .off else { return [] }
        return [IntegrationAction(id: "settings", title: "Настройки чата…") { [weak self] in self?.showSettings() }]
    }

    func start() async {
        cachedKey = keychain.read()
        await findClaude()
        if claudeCLI == nil {
            searchAgain = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    guard let self, self.conversation != nil, self.claudeCLI == nil else { return }
                    await self.findClaude()
                }
            }
        }
        preferences.hasKey = !(cachedKey ?? "").isEmpty
        preferences.onRouteChange = { [weak self] in
            self?.conversation?.clear()
            self?.refreshStatus()
        }
        let preferences = self.preferences
        let transport = RoutingTransport(route: { preferences.route },
                                         cli: { [weak self] in self?.cliTransport })
        conversation = ChatConversation(
            transport: transport,
            apiKey: { [weak self] in
                guard let self else { return nil }
                return preferences.route == .subscription ? "subscription" : self.cachedKey
            },
            model: { preferences.model },
            setupHint: { preferences.setupHint },
            caption: { preferences.route.caption })
        refreshStatus()
    }

    /// Looks for the CLI and, if found, routes the subscription chat through it.
    private func findClaude() async {
        claudeCLI = await Task.detached { ClaudeCodeChatTransport.locate() }.value
        cliTransport = claudeCLI.map { ClaudeCodeChatTransport(executable: $0) }
        preferences.claudeFound = claudeCLI != nil
        if claudeCLI != nil { searchAgain?.cancel() }
        if conversation != nil { refreshStatus() }
    }

    func stop() async {
        searchAgain?.cancel()
        searchAgain = nil
        conversation?.clear()
        conversation = nil
        cachedKey = nil
        cliTransport = nil
        status = .off
    }

    private func refreshStatus() {
        guard conversation != nil else { status = .off; return }
        status = preferences.setupHint.map(IntegrationStatus.needsSetup) ?? .running
    }

    func showSettings() {
        if claudeCLI == nil {
            Task { [weak self] in
                await self?.findClaude()
                if self?.claudeCLI != nil { self?.presentSettings() }
            }
        }
        presentSettings()
    }

    private func presentSettings() {
        settingsWindow?.close()
        let view = ChatSettingsView(
            route: preferences.route, hasKey: preferences.hasKey, claudeFound: preferences.claudeFound,
            model: preferences.model,
            save: { [weak self] route, key, model in
                guard let self else { return }
                if let key {
                    try self.keychain.save(key)
                    self.cachedKey = key
                    self.preferences.hasKey = true
                }
                self.preferences.route = route
                self.preferences.model = model
                self.refreshStatus()
            },
            removeKey: { [weak self] in
                self?.keychain.delete()
                self?.cachedKey = nil
                self?.preferences.hasKey = false
                self?.refreshStatus()
            },
            close: { [weak self] in
                self?.settingsWindow?.close()
                self?.settingsWindow = nil
            })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Mely — чат с Claude"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Sends each question the way the settings say, at the moment it is asked.
private struct RoutingTransport: ChatTransport, @unchecked Sendable {
    let route: @MainActor () -> ChatRoute
    let cli: @MainActor () -> ClaudeCodeChatTransport?
    private let api = URLSessionChatTransport()

    init(route: @escaping @MainActor () -> ChatRoute, cli: @escaping @MainActor () -> ClaudeCodeChatTransport?) {
        self.route = route
        self.cli = cli
    }

    func stream(apiKey: String, model: ChatModel, history: [ChatTurn]) -> AsyncThrowingStream<SSEEvent, Error> {
        let (route, cli) = MainActor.assumeIsolated { (self.route(), self.cli()) }
        log.info("chat route=\(String(describing: route), privacy: .public) cli=\(cli != nil)")
        if route == .subscription, let cli { return cli.stream(apiKey: apiKey, model: model, history: history) }
        return api.stream(apiKey: apiKey, model: model, history: history)
    }

    func reset() {
        MainActor.assumeIsolated { cli()?.reset() }
    }
}
