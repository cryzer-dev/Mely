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
    private let reminders = RemindersIntegration()
    private let nowPlaying = NowPlayingIntegration()
    private let tabs = IslandTabs()
    private let whatsNew = WhatsNewState()
    private let inboxSettings = InboxSettings()
    private let telemetry = Telemetry()
    private lazy var inbox = NotificationInbox(fileURL: inboxSettings.persists ? NotificationInbox.defaultURL : nil)
    private var chatHotKey: GlobalHotKey?
    private var sessions: ClaudeSessionsController?
    private let characterSettings = CharacterSettings()
    private let desktopPresence = DesktopPresence()
    private var desktopMely: DesktopMelyController?
    private let behavior = IslandBehavior()
    private let updateState = UpdateState(currentVersion: AppInfo.version, releasesURL: UpdateController.releasesURL)
    private var updates: UpdateController?
    private let fullScreen = FullScreenWatcher()
    private lazy var settings = SettingsWindowController(registry: registry, characters: characterSettings, behavior: behavior,
                                                         updates: updateState, peeks: nowPlaying.peeks, inbox: inboxSettings,
                                                         telemetry: telemetry.settings,
                                                         displayChanged: { [weak self] in self?.island?.relocateToChosenScreen() })

    func applicationWillTerminate(_ notification: Notification) {
        inbox.saveNow()
        // Deleted tasks still inside their «Отменить» window go now.
        reminders.flushDeletes()
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
            expanded: { [chat, notifications, calendar, reminders, nowPlaying, tabs, updateState, inbox, inboxSettings, telemetry, whatsNew] in
                WithCharacter(settings: character, desktop: desktop) { ExpandedIsland(sessions: sessions, chat: chat, notifications: notifications, calendar: calendar,
                               reminders: reminders, nowPlaying: nowPlaying, whatsNew: whatsNew,
                               tryTasks: { [weak self] in self?.tryTasks() }, tabs: tabs, updates: updateState,
                               inbox: inbox, inboxSettings: inboxSettings, count: { telemetry.count($0) },
                               enableCalendar: { [weak self] in
                                   guard let self else { return }
                                   Task { await self.registry.setEnabled("calendar", true) }
                               }) }
            },
            header: { [chat, notifications, calendar, reminders, nowPlaying, tabs, behavior, updateState, inbox, inboxSettings] in
                ExpandedHeader(sessions: sessions, chat: chat, notifications: notifications, calendar: calendar, reminders: reminders,
                               nowPlaying: nowPlaying,
                               tabs: tabs, behavior: behavior, updates: updateState,
                               inbox: inbox, inboxSettings: inboxSettings,
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
        // Approvals and questions hold the island; so does typing in the chat or the tasks,
        // and carrying Mely out of it.
        let presence = desktopPresence
        island?.machine.isHeldOpen = { [weak model, weak self] in
            (model?.holdsIslandOpen ?? false)
                || ([.chat, .tasks].contains(self?.tabs.selected) && self?.island?.hasKeyboard == true)
                || presence.isDragging
        }
        island?.isCarrying = { presence.isDragging }
        island?.escapeOverride = { [weak self] in
            guard let self else { return false }
            // Esc closes «Что нового» first; the island stays open.
            if self.whatsNew.isShowing {
                self.whatsNew.dismiss()
                return true
            }
            return self.tabs.handleEscape()
        }
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
                self.fullScreenChanged()
            }
        }
        watchFullScreen(desktop: desktop)
        if behavior.launchGreeting {
            island?.greet()
            SoundEngine.shared.play(.greet)
        } else {
            island?.reveal()
        }
        let firstRun = showFirstRunTips()
        setUpStatusItem()
        setUpEditMenu()
        registry.permissions = permissions
        registry.register(claudeCode)
        registry.register(chat)
        let inbox = inbox, inboxSettings = inboxSettings
        inboxSettings.changed = { inbox.apply(inboxSettings) }
        notifications.inbox = inbox
        notifications.inboxSettings = inboxSettings
        calendar.inbox = inbox
        calendar.inboxSettings = inboxSettings
        registry.register(notifications)
        registry.register(calendar)
        registry.register(reminders)
        registry.register(nowPlaying)
        nowPlaying.peek = { [weak self] in self?.island?.showPeek($0, for: .seconds(4)) }
        reminders.peek = { [weak self] in self?.island?.showPeek($0, for: .seconds(4)) }
        calendar.peek = { [weak self] content in
            // An event reminder stays until the event ends (`lastsUntil`); the rest, five seconds.
            self?.island?.showPeek(content)
        }
        calendar.dismissPeek = { [weak self] id in self?.island?.dismissPeek(id) }
        calendar.joined = { [weak self] in self?.telemetry.count(.meetingJoined) }
        island?.onPeekDismiss = { [weak self] id in self?.calendar.forgetPeek(id) }
        island?.onPeekAction = { [weak self] id in
            guard let self else { return }
            if id.hasPrefix(Self.updatePeekPrefix) {
                self.updateState.installNow()
            } else if id == Self.telemetryPeekId {
                // Off, and the settings open on the switch: it is plain what happened.
                self.telemetry.settings.isOn = false
                self.telemetry.settings.reveal += 1
                self.openSettings(on: .general)
            } else if id.hasPrefix(Self.updatedPeekPrefix) {
                let version = String(id.dropFirst(Self.updatedPeekPrefix.count))
                // A release with a card shows it in the island; others open their page.
                if self.whatsNew.card.matches(version) {
                    self.whatsNew.show()
                    self.island?.expandForAlert()
                } else if let url = self.updateState.notesURL(for: version) {
                    NSWorkspace.shared.open(url)
                }
            } else if id.hasPrefix(RemindersIntegration.duePrefix) {
                self.reminders.runPeekAction(id)
            } else {
                self.calendar.runPeekAction(id)
            }
        }
        island?.onPeekSecondary = { [weak self] id in self?.reminders.runPeekSecondary(id) }
        island?.onPeekOpen = { [weak self] id in self?.notifications.openPreview(id) ?? false }
        notifications.peek = { [weak self] in self?.island?.showPeek($0) }
        // Mely reminds of due tasks itself: Reminders' own banners are not mirrored then.
        notifications.suppressedApps = { [weak self] in
            guard let reminders = self?.reminders, reminders.status == .running, reminders.settings.remindsUnderNotch else { return [] }
            return RemindersIntegration.notificationSources
        }
        island?.presentation.dropFiles = { [weak self] urls in self?.attachToChat(urls) }
        chatHotKey = GlobalHotKey { [weak self] in self?.openChat() }
        desktop.start()
        Task { await registry.startEnabled() }
        telemetry.integrations = { [registry] in registry.enabledIds.sorted() }
        telemetry.start()
        if !firstRun { announceTelemetry() }
        startUpdates()
    }

    static let updatePeekPrefix = "update-available-"
    static let updatedPeekPrefix = "updated-"

    /// «Попробовать задачи»: on (macOS asks for Reminders once), then the tab.
    private func tryTasks() {
        whatsNew.dismiss()
        Task { [weak self] in
            guard let self else { return }
            if !self.registry.isEnabled(self.reminders.id) { await self.registry.setEnabled(self.reminders.id, true) }
            if self.reminders.status == .running { self.tabs.showTask(nil) } else { self.openSettings(on: .integrations) }
        }
    }

    /// Daily checks for a new version (Sparkle); after an update, «Обновилась до …» with «Что нового».
    private func startUpdates() {
        let updates = UpdateController(state: updateState)
        updates.announce = { [weak self] version in self?.announceUpdate(version) }
        updates.start()
        self.updates = updates
        if let version = UpdateState.justUpdated(current: AppInfo.version) {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(GreetingView.duration + 0.5))
                guard let self else { return }
                let notes = self.updateState.notesURL(for: version)
                self.island?.showPeek(PeekContent(id: Self.updatedPeekPrefix + version, symbol: "sparkles", tint: .green,
                                                  title: "Обновилась до \(version)",
                                                  subtitle: notes == nil ? "Новая версия установлена" : "Посмотрите, что изменилось",
                                                  actionTitle: notes == nil ? nil : "Что нового"), for: .seconds(8))
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
        let settingsItem = NSMenuItem(title: "Настройки…", action: #selector(openSettings as () -> Void), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти из \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// ⌘C, ⌘V, ⌘X, ⌘A, ⌘Z in the chat and the settings fields (issue #4). AppKit sends them
    /// through the main menu's key equivalents; an agent app has no menu bar, so without this
    /// menu the keys reach nothing. Never shown: only its shortcuts are used.
    private func setUpEditMenu() {
        let main = NSMenu()
        // AppKit takes the first item as the app menu.
        main.addItem(NSMenuItem(title: AppInfo.name, action: nil, keyEquivalent: ""))
        main.items[0].submenu = NSMenu(title: AppInfo.name)
        let edit = NSMenu(title: "Правка")
        edit.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Скопировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let plain = edit.addItem(withTitle: "Вставить без оформления", action: #selector(NSTextView.pasteAsPlainText(_:)),
                                 keyEquivalent: "V")
        plain.keyEquivalentModifierMask = [.command, .option, .shift]
        edit.addItem(withTitle: "Выбрать все", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Правка", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
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
    /// True when shown this launch.
    @discardableResult
    private func showFirstRunTips() -> Bool {
        let key = "firstRunTipsShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.set(true, forKey: key)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(GreetingView.duration + 1.2))
            self?.island?.showPeek(PeekContent(
                id: "first-run", symbol: "hand.wave.fill", tint: .green, title: "Нажми на челку — там всё",
                subtitle: "⌃⌥Пробел — чат с Claude · Mely можно вытащить на стол · настройки — шестерёнка в челке"),
                for: .seconds(10))
        }
        return true
    }

    /// Once, on a launch without the first-run tips: statistics are on; «Отключить» turns them
    /// off and opens the settings on the switch.
    private func announceTelemetry() {
        guard telemetry.settings.isOn, !telemetry.settings.announced else { return }
        telemetry.settings.announced = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(GreetingView.duration + 1.2))
            self?.island?.showPeek(PeekContent(
                id: Self.telemetryPeekId, symbol: "chart.bar.fill", tint: .blue, title: "Помогите улучшить Mely",
                subtitle: "Mely анонимно считает, какими функциями пользуются чаще", actionTitle: "Отключить"),
                for: .seconds(8))
        }
    }

    static let telemetryPeekId = "telemetry-notice"

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

    /// Mely gives way to full-screen apps as «Полноэкранные приложения» says.
    private func watchFullScreen(desktop: DesktopMelyController) {
        let behavior = behavior, fullScreen = fullScreen
        island?.fullScreenMode = { behavior.fullScreenMode }
        island?.fullScreenTaken = { fullScreen.covers($0) }
        desktop.yieldsTo = { behavior.fullScreenMode != .normal && fullScreen.covers($0) }
        SoundEngine.shared.isQuiet = { [weak self] sound in
            guard self?.island?.yieldsToFullScreen == true else { return false }
            return !behavior.fullScreenMode.allows(isRequest: sound == .approval || sound == .question)
        }
        fullScreen.onChange = { [weak self] in self?.fullScreenChanged() }
        fullScreen.start()
    }

    private func fullScreenChanged() {
        island?.fullScreenChanged()
        desktopMely?.fullScreenChanged()
    }

    @objc private func openSettings() {
        openSettings(on: nil)
    }

    private func openSettings(on section: SettingsSection?) {
        settings.foldIsland = { [weak self] in self?.island?.collapseFromHeader() }
        settings.islandArea = { [weak self] in self?.island?.restingArea }
        settings.show(section)
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
    let reminders: RemindersIntegration
    let nowPlaying: NowPlayingIntegration
    let whatsNew: WhatsNewState
    /// «Попробовать задачи» on «Что нового».
    let tryTasks: () -> Void
    let tabs: IslandTabs
    let updates: UpdateState
    let inbox: NotificationInbox
    let inboxSettings: InboxSettings
    /// Usage statistics: the island opened, a tab shown.
    let count: (UsageCounter) -> Void
    /// Switches the calendar integration on (macOS then asks for calendar access).
    let enableCalendar: () -> Void

    var body: some View {
        // Mely big on the left; in the chat it reacts to the answer. A waiting version: «Обновить» under it.
        HStack(alignment: .top, spacing: 12) {
            LivePose(sessions: sessions, nowPlaying: nowPlaying) { pose in
                ChatAwarePose(conversation: tabs.selected == .chat ? chat.conversation : nil,
                              fallback: reminders.celebrating ? TaskCelebration.pose(pose) : pose)
            }
            .updatePill(updates.pendingVersion, action: updates.installNow)
            .frame(width: 88)
            .padding(.top, 14)
            content
        }
        // Shown afresh on each opening of the island.
        .onAppear {
            whatsNew.showIfNew(appVersion: AppInfo.version)
            count(.islandOpened)
            count(.tabOpened(Self.usageTab(tabs.selected)))
        }
        .onChange(of: tabs.selected) { count(.tabOpened(Self.usageTab(tabs.selected))) }
    }

    static func usageTab(_ tab: IslandTabs.Tab) -> UsageCounter.Tab {
        switch tab {
        case .sessions: .sessions
        case .chat: .chat
        case .today: .today
        case .tasks: .tasks
        case .music: .music
        case .notifications: .notifications
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
                       notifications: NotificationsTab.isShown(notifications: notifications, calendar: calendar, settings: inboxSettings)
                           ? AnyView(NotificationsView(inbox: inbox) { [tabs] item in
                               if item.isCalendar {
                                   inbox.remove(item.id)
                                   tabs.selected = .today
                               } else {
                                   notifications.open(item)
                               }
                           })
                           : nil,
                       // Always there: switched off, it offers to connect the calendar.
                       today: AnyView(AgendaView(agenda: calendar.agenda, isOn: calendar.status != .off, tasks: todayTasks,
                                                 enable: enableCalendar) { event in
                           if let link = event.meeting { calendar.join(link) }
                       }),
                       tasks: reminders.status == .running ? AnyView(tasksPage) : nil,
                       music: nowPlaying.status == .running && nowPlaying.model.isVisible()
                           ? AnyView(MiniPlayerView(model: nowPlaying.model, peeks: nowPlaying.peeks, send: { nowPlaying.send($0) },
                                                    seek: { nowPlaying.seek(to: $0) },
                                                    openSource: { nowPlaying.openSource($0) }))
                           : nil,
                       whatsNew: whatsNew.isShowing ? AnyView(WhatsNewView(card: whatsNew.card, tryTasks: tryTasks,
                                                                           done: { [whatsNew] in whatsNew.dismiss() },
                                                                           more: whatsNewNotes)) : nil,
                       open: { HostActivator.activate($0.host, origin: $0.origin) },
                       decide: { [weak sessions] in sessions?.decide($0, $1) },
                       answerInTerminal: { [weak sessions] in sessions?.answerInTerminal($0) })
    }
}

extension ExpandedIsland {
    /// «Подробнее ↗»: this release's page, when the version has one.
    var whatsNewNotes: (() -> Void)? {
        guard let url = updates.notesURL(for: AppInfo.version) else { return nil }
        return { NSWorkspace.shared.open(url) }
    }

    /// Today's tasks under the events, while the tasks are on and shown there.
    var todayTasks: TodayTasks? {
        guard reminders.status == .running, reminders.settings.showsInToday else { return nil }
        let reminders = reminders, tabs = tabs
        return TodayTasks(items: reminders.items, toggle: { reminders.setCompleted($0, $1) }) { id in
            // The task must be in sight: «Сегодня», no list or tag narrowing it.
            reminders.settings.filter = TaskFilter(period: .today)
            tabs.showTask(id)
        }
    }

    var tasksPage: some View {
        var actions = TasksActions()
        let reminders = reminders
        actions.setCompleted = { reminders.setCompleted($0, $1) }
        actions.create = { reminders.create($0) }
        actions.rename = { reminders.rename($0, to: $1) }
        actions.setDue = { reminders.setDue($0, $1) }
        actions.moveToDay = { reminders.move($0, toDayOf: $1) }
        actions.setPriority = { reminders.setPriority($0, $1) }
        actions.setMarks = { reminders.setMarks($0, $1) }
        actions.moveToList = { reminders.move($0, toList: $1) }
        actions.moveOverdueToToday = { reminders.moveOverdueToToday($0) }
        actions.open = { reminders.open($0) }
        actions.delete = { reminders.delete($0) }
        actions.undoDelete = { reminders.undoDelete($0) }
        return TasksView(items: reminders.items, lists: reminders.lists, hasLoaded: reminders.hasLoaded,
                         settings: reminders.settings, tabs: tabs, actions: actions)
    }
}

/// The expanded island's top row (task 7.9): the sections that exist right now, the plan,
/// sound, settings and «×».
private struct ExpandedHeader: View {
    let sessions: ClaudeSessionsController
    let chat: ClaudeChatIntegration
    let notifications: NotificationMirrorIntegration
    let calendar: CalendarIntegration
    let reminders: RemindersIntegration
    let nowPlaying: NowPlayingIntegration
    let tabs: IslandTabs
    let behavior: IslandBehavior
    let updates: UpdateState
    let inbox: NotificationInbox
    let inboxSettings: InboxSettings
    let openSettings: () -> Void
    let close: () -> Void

    var body: some View {
        var items = [IslandHeader.Item(.sessions, icon: "house.fill", title: "Claude Code")]
        if chat.conversation != nil { items.append(.init(.chat, icon: "bubble.left.fill", title: "Чат")) }
        items.append(.init(.today, icon: "calendar", title: "Сегодня"))
        if reminders.status == .running { items.append(.init(.tasks, icon: "checklist", title: "Задачи")) }
        if nowPlaying.status == .running && nowPlaying.model.isVisible() {
            items.append(.init(.music, icon: "music.note", title: "Музыка"))
        }
        if NotificationsTab.isShown(notifications: notifications, calendar: calendar, settings: inboxSettings) {
            items.append(.init(.notifications, icon: "bell.fill", title: "Уведомления", badge: inbox.unseen))
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

/// A task just done: Mely is glad for a moment, unless something matters more.
enum TaskCelebration {
    static func pose(_ pose: CharacterPose) -> CharacterPose {
        switch pose {
        case .worried, .curious, .scared, .sad: pose
        default: .happy
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

/// The "Уведомления" tab is there while one of its sources is on and kept in it.
@MainActor
enum NotificationsTab {
    static func isShown(notifications: NotificationMirrorIntegration, calendar: CalendarIntegration, settings: InboxSettings) -> Bool {
        (notifications.status != .off && settings.keepsMessages) || (calendar.status != .off && settings.keepsCalendar)
    }
}
