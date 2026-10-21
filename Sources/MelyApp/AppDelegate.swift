import AppKit
import SwiftUI
import MelyCore
import MelyUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var island: IslandWindowController?
    // The chat is on from the start: without a key it shows where to add one, nothing more.
    private let registry = IntegrationRegistry(enabledByDefault: ["claude-code", "claude-chat", "now-playing"])
    private let islandModel = IslandModel()
    private let permissions = SystemPermissions()
    private let claudeCode = ClaudeCodeIntegration()
    private let chat = ClaudeChatIntegration()
    private let notifications = NotificationMirrorIntegration()
    private let calendar = CalendarIntegration()
    private let nowPlaying = NowPlayingIntegration()
    private let tabs = IslandTabs()
    private var chatHotKey: GlobalHotKey?
    private var sessions: ClaudeSessionsController?
    private let characterSettings = CharacterSettings()
    private let desktopPresence = DesktopPresence()
    private var desktopMely: DesktopMelyController?
    private let behavior = IslandBehavior()
    private let updateState = UpdateState(currentVersion: AppInfo.version, releasesURL: UpdateController.releasesURL)
    private var updates: UpdateController?
    private lazy var settings = SettingsWindowController(registry: registry, characters: characterSettings, behavior: behavior,
                                                         updates: updateState,
                                                         displayChanged: { [weak self] in self?.island?.relocateToChosenScreen() })

    func applicationWillTerminate(_ notification: Notification) {
        DevBuildSwap.handBack()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard DevBuildSwap.takeOver() else { NSApp.terminate(nil); return }
        SoundEngine.shared.behavior = behavior
        let character = characterSettings
        let model = islandModel
        let sessions = ClaudeSessionsController(island: model,
                                                reveal: { [weak self] in self?.island?.flashWings() },
                                                expand: { [weak self] in self?.island?.expandForAlert() },
                                                peek: { [weak self] in self?.island?.showPeek($0) })
        self.sessions = sessions
        let store = sessions.store
        let nowPlaying = nowPlaying
        // Mely out of the notch (task 6.8): the same pose as in the island.
        let desktop = DesktopMelyController(presence: desktopPresence) { model in
            AnyView(WithCharacter(settings: character) {
                LivePose(sessions: sessions, nowPlaying: nowPlaying) { DesktopMelyFace(model: model, pose: $0) }
            })
        }
        desktopMely = desktop
        island = IslandWindowController(
            compactLeading: { [nowPlaying] in
                WithCharacter(settings: character, desktop: desktop) {
                    LivePose(sessions: sessions, nowPlaying: nowPlaying) { CompactLeading(music: nowPlaying.model, pose: $0) }
                }
            },
            compactTrailing: AnyView(CompactSessionStatus(store: store, usage: sessions.usage, music: nowPlaying.model)),
            expanded: { [chat, notifications, calendar, nowPlaying, tabs] in
                WithCharacter(settings: character, desktop: desktop) { ExpandedIsland(sessions: sessions, chat: chat, notifications: notifications, calendar: calendar,
                               nowPlaying: nowPlaying, tabs: tabs,
                               enableCalendar: { [weak self] in
                                   guard let self else { return }
                                   Task { await self.registry.setEnabled("calendar", true) }
                               }) }
            },
            header: { [chat, notifications, nowPlaying, tabs, behavior, updateState] in
                ExpandedHeader(sessions: sessions, chat: chat, notifications: notifications, nowPlaying: nowPlaying,
                               tabs: tabs, behavior: behavior, updates: updateState,
                               openSettings: { [weak self] in self?.openSettings() },
                               close: { [weak self] in self?.island?.collapseFromHeader() })
            })
        // Waiting requests keep the wings out; other events flash them (task 1.6).
        island?.wingsPinned = { [weak sessions] in !(sessions?.queue.requests.isEmpty ?? true) }
        island?.wingsLive = { [weak sessions, weak self] in
            guard let sessions else { return false }
            return IslandWings.live(states: sessions.store.sessions.map(\.state), usage: sessions.usage.usage)
                || self?.nowPlaying.model.current?.isPlaying == true
        }
        // Approvals and questions hold the island; so does typing in the chat, and
        // carrying Mely out of it.
        let presence = desktopPresence
        island?.machine.isHeldOpen = { [weak model, weak self] in
            (model?.holdsIslandOpen ?? false)
                || (self?.tabs.selected == .chat && self?.island?.hasKeyboard == true)
                || presence.isDragging
        }
        island?.isCarrying = { presence.isDragging }
        desktop.islandFrame = { [weak self] in self?.island?.screenFrame ?? .zero }
        desktop.alertActive = { [weak sessions] in !(sessions?.queue.requests.isEmpty ?? true) }
        desktop.busy = { [weak sessions] in
            sessions?.store.sessions.contains { $0.state == .working || $0.state == .thinking } ?? false
        }
        desktop.askAbout = { [weak self] app, frame in self?.askAbout(app, frame) }
        desktop.openSettings = { [weak self] in self?.openSettings() }
        desktop.collapseIsland = { [weak self] in self?.island?.collapse() }
        claudeCode.onEvent = { [weak sessions] event, origin, responder in
            sessions?.handle(event, origin: origin, responder: responder)
        }
        if let machine = island?.machine {
            behavior.apply(to: machine)
            behavior.onChange = { [weak self, weak machine] in
                guard let self, let machine else { return }
                self.behavior.apply(to: machine)
            }
        }
        if behavior.launchGreeting {
            island?.greet()
            SoundEngine.shared.play(.greet)
        } else {
            island?.reveal()
        }
        showFirstRunTips()
        setUpStatusItem()
        registry.permissions = permissions
        registry.register(claudeCode)
        registry.register(chat)
        registry.register(notifications)
        registry.register(calendar)
        registry.register(nowPlaying)
        nowPlaying.peek = { [weak self] in self?.island?.showPeek($0, for: .seconds(4)) }
        calendar.peek = { [weak self] content in
            // A meeting reminder stays until the meeting (`until`); the rest, five seconds.
            self?.island?.showPeek(content)
        }
        island?.onPeekAction = { [weak self] id in
            if id.hasPrefix(Self.updatePeekPrefix) { self?.updateState.installNow() } else { self?.calendar.runPeekAction(id) }
        }
        island?.onPeekOpen = { [weak self] id in self?.notifications.openPreview(id) ?? false }
        notifications.peek = { [weak self] in self?.island?.showPeek($0) }
        island?.presentation.dropFiles = { [weak self] urls in self?.attachToChat(urls) }
        chatHotKey = GlobalHotKey { [weak self] in self?.openChat() }
        desktop.start()
        Task { await registry.startEnabled() }
        startUpdates()
    }

    static let updatePeekPrefix = "update-available-"

    /// Daily checks for a new version (Sparkle); after an update, «Обновилась до …».
    private func startUpdates() {
        let updates = UpdateController(state: updateState)
        updates.announce = { [weak self] version in self?.announceUpdate(version) }
        updates.start()
        self.updates = updates
        if let version = UpdateState.justUpdated(current: AppInfo.version) {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(GreetingView.duration + 0.5))
                self?.island?.showPeek(PeekContent(id: "updated", symbol: "sparkles", tint: .green,
                                                   title: "Обновилась до \(version)",
                                                   subtitle: "Что нового — в настройках, «Все версии»"))
            }
        }
    }

    /// Once per version, and not over a waiting request or during a Focus: then it waits.
    private func announceUpdate(_ version: String) {
        let busy = !(sessions?.queue.requests.isEmpty ?? true) || SystemFocus.isOn()
        if busy {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                self?.announceUpdate(version)
            }
            return
        }
        guard updateState.shouldAnnounce(version) else { return }
        island?.showPeek(PeekContent(id: Self.updatePeekPrefix + version, symbol: "arrow.down.circle.fill", tint: .green,
                                     title: "Доступна Mely \(version)", subtitle: "Новая версия готова к установке",
                                     actionTitle: "Обновить"), for: .seconds(8))
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MelyLogo.menuBarImage()
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти из \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// ⌃⌥Space: the chat tab with the cursor in the field. Without the chat integration,
    /// its settings, so the shortcut never does nothing.
    private func openChat(captureWindow: Bool = true) {
        guard let conversation = chat.conversation else { openSettings(); return }
        // Read the window before the island takes the keyboard. A dropped file is its own
        // context (the window would just be Finder).
        if captureWindow { WindowContext.capture { conversation.offer(context: $0) } }
        tabs.showChat()
        island?.expandForTyping()
    }

    /// The very first launch (task 7.6): after the greeting, where things are.
    private func showFirstRunTips() {
        let key = "firstRunTipsShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(GreetingView.duration + 1.2))
            self?.island?.showPeek(PeekContent(
                id: "first-run", symbol: "hand.wave.fill", tint: .green, title: "Нажми на челку — там всё",
                subtitle: "⌃⌥Пробел — чат с Claude · Mely можно вытащить на стол · настройки — шестерёнка в челке"),
                for: .seconds(10))
        }
    }

    /// Mely dropped on a window: a new conversation about that window.
    private func askAbout(_ app: NSRunningApplication, _ frame: CGRect) {
        guard let conversation = chat.conversation else { openSettings(); return }
        WindowContext.capture(app: app, frame: frame) { context in
            if let context { conversation.ask(about: context) }
        }
        tabs.showChat()
        island?.expandForTyping()
    }

    /// A file dropped on the notch goes to the next question.
    private func attachToChat(_ urls: [URL]) {
        guard let conversation = chat.conversation else { return }
        SoundEngine.shared.play(.drop)
        conversation.attach(urls)
        openChat(captureWindow: false)
    }

    @objc private func openSettings() {
        settings.show()
    }
}

/// Expanded island: reads the chat integration in its body, so the chat tab comes and
/// goes with it.
private struct ExpandedIsland: View {
    static let claudeDesktopInstalled =
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: ClaudeDesktopHandoff.bundleId) != nil

    /// A new chat in the Claude app with this conversation in the field.
    @MainActor static func openInClaude(_ conversation: ChatConversation) {
        guard let url = ClaudeDesktopHandoff.url(for: ClaudeDesktopHandoff.prompt(for: conversation)) else { return }
        NSWorkspace.shared.open(url)
    }

    let sessions: ClaudeSessionsController
    let chat: ClaudeChatIntegration
    let notifications: NotificationMirrorIntegration
    let calendar: CalendarIntegration
    let nowPlaying: NowPlayingIntegration
    let tabs: IslandTabs
    /// Switches the calendar integration on (macOS then asks for calendar access).
    let enableCalendar: () -> Void

    var body: some View {
        // Mely big on the left; in the chat it reacts to the answer.
        HStack(alignment: .top, spacing: 12) {
            LivePose(sessions: sessions, nowPlaying: nowPlaying) { pose in
                ChatAwarePose(conversation: tabs.selected == .chat ? chat.conversation : nil, fallback: pose)
            }
            .frame(width: 72)
            .padding(.top, 18)
            content
        }
    }

    private var content: some View {
        let conversation = chat.conversation
        return ClaudeOverview(store: sessions.store, queue: sessions.queue, usage: sessions.usage,
                       tabs: tabs,
                       chat: conversation.map { c in
                           AnyView(ChatView(conversation: c, preferences: chat.preferences, tabs: tabs,
                                                     openSettings: { [weak chat] in chat?.showSettings() },
                                                     openInClaude: Self.claudeDesktopInstalled ? { Self.openInClaude(c) } : nil))
                       },
                       messages: notifications.messages.map { m in
                           AnyView(MessagesView(messages: m) { notifications.open(id: $0) })
                       },
                       messagesBadge: notifications.messages?.unseen ?? 0,
                       // Always there: switched off, it offers to connect the calendar.
                       today: AnyView(AgendaView(agenda: calendar.agenda, isOn: calendar.status != .off,
                                                 enable: enableCalendar) { event in
                           if let link = event.meeting { calendar.join(link) }
                       }),
                       music: nowPlaying.status == .running && nowPlaying.model.isVisible()
                           ? AnyView(MiniPlayerView(model: nowPlaying.model, send: { nowPlaying.send($0) },
                                                    openSource: { nowPlaying.openSource($0) }))
                           : nil,
                       open: { HostActivator.activate($0.host, origin: $0.origin) },
                       decide: { [weak sessions] in sessions?.decide($0, $1) },
                       answerInTerminal: { [weak sessions] in sessions?.answerInTerminal($0) })
    }
}

/// The expanded island's top row (task 7.9): the sections that exist right now, the plan,
/// sound, settings and «×».
private struct ExpandedHeader: View {
    let sessions: ClaudeSessionsController
    let chat: ClaudeChatIntegration
    let notifications: NotificationMirrorIntegration
    let nowPlaying: NowPlayingIntegration
    let tabs: IslandTabs
    let behavior: IslandBehavior
    let updates: UpdateState
    let openSettings: () -> Void
    let close: () -> Void

    var body: some View {
        var items = [IslandHeader.Item(.sessions, icon: "house.fill", title: "Claude Code")]
        if chat.conversation != nil { items.append(.init(.chat, icon: "bubble.left.fill", title: "Чат")) }
        items.append(.init(.today, icon: "calendar", title: "Сегодня"))
        if nowPlaying.status == .running && nowPlaying.model.isVisible() {
            items.append(.init(.music, icon: "music.note", title: "Музыка"))
        }
        if let messages = notifications.messages {
            items.append(.init(.messages, icon: "bell.fill", title: "Сообщения", badge: messages.unseen))
        }
        return IslandHeader(tabs: tabs, items: items, usage: sessions.usage, soundOn: behavior.soundOn,
                            heldOpen: !sessions.queue.requests.isEmpty,
                            updateAvailable: updates.hasPendingUpdate,
                            toggleSound: {
                                behavior.soundOn.toggle()
                                if behavior.soundOn { SoundEngine.shared.play(.pop) }
                            },
                            openSettings: openSettings, close: close)
    }
}

/// Hands the chosen look down to every character view; re-read every minute so a season
/// dresses Mely on its first day. In the island, Mely can also be carried out.
private struct WithCharacter<Content: View>: View {
    let settings: CharacterSettings
    var desktop: DesktopMelyController? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        // Read here, so the island follows Mely leaving and coming back.
        let drag = desktop?.drag()
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content()
                .environment(\.characterAppearance, settings.appearance(now: context.date))
                .environment(\.characterDrag, drag)
        }
    }
}

/// Mely on the desktop: the pose of the moment, asleep when nothing goes on, a little
/// bigger under the pointer.
private struct DesktopMelyFace: View {
    let model: DesktopMelyModel
    let pose: CharacterPose

    var body: some View {
        MelyCharacter(pose: model.carried ?? (model.asleep ? .sleeping : pose))
            .padding(14)
            .scaleEffect(model.hovered ? 1.07 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: model.hovered)
    }
}

/// Mely's pose of the moment from everything going on: reads the stores in its body, so
/// the pose follows them.
private struct LivePose<Content: View>: View {
    let sessions: ClaudeSessionsController
    let nowPlaying: NowPlayingIntegration
    @ViewBuilder let content: (CharacterPose) -> Content

    var body: some View {
        let states = sessions.store.sessions
        let inputs = CharacterInputs(
            sessions: states.map(\.state),
            lastActivity: states.map(\.lastSeen).max(),
            pendingApprovals: sessions.queue.requests.filter { !$0.isQuestion }.count,
            pendingQuestions: sessions.queue.requests.filter(\.isQuestion).count,
            musicPlaying: nowPlaying.model.current?.isPlaying == true,
            planPercent: sessions.usage.usage?.current().fullest?.usedPercent)
        // Re-read every minute: falling asleep depends on time alone.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(CharacterMood.pose(inputs, now: context.date))
        }
    }
}

/// The big Mely: the chat's reaction while the chat tab is open, otherwise `fallback`.
private struct ChatAwarePose: View {
    let conversation: ChatConversation?
    let fallback: CharacterPose

    var body: some View {
        // Wakes once more when the reaction to an answer runs out.
        let end = conversation?.answeredAt.map { [$0.addingTimeInterval(ChatConversation.reactionTime)] } ?? []
        TimelineView(.explicit(end)) { context in
            MelyStage(pose: conversation?.characterPose(now: context.date) ?? fallback)
        }
    }
}
