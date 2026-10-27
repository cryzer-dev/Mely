import AppKit
import SwiftUI
import MelyCore
import MelyUI

/// Sample data and island builders shared by the snapshots and the layout checks.
@MainActor
public enum Fixtures {
    // MARK: Screens

    public struct Screen: Sendable {
        public let name: String
        public let geometry: IslandScreenGeometry
    }

    public static let macBook14 = Screen(name: "MacBook14", geometry: IslandScreenGeometry(
        screenWidth: 1512, safeAreaTop: 32, auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32))
    /// A taller menu bar and a wider notch.
    public static let macBook16 = Screen(name: "MacBook16", geometry: IslandScreenGeometry(
        screenWidth: 1728, safeAreaTop: 38, auxiliaryLeftWidth: 762, auxiliaryRightWidth: 762, menuBarHeight: 38))
    public static let external = Screen(name: "External", geometry: IslandScreenGeometry(
        screenWidth: 2560, safeAreaTop: 0, auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 25))
    public static let screens = [macBook14, macBook16, external]

    // MARK: The island

    /// The expanded island as the app lays it out: the header level with the notch, the big
    /// Mely left, the section right (tasks 7.9, 7.10).
    public static func expandedApp<C: View>(_ tab: IslandTabs.Tab, geometry: IslandScreenGeometry? = nil,
                                            held: Bool = false, showsUsage: Bool = false, pose: CharacterPose = .idle,
                                            usage: PlanUsageStore? = nil, updateAvailable: Bool = false,
                                            backdrop: Color = Color(white: 0.85),
                                            @ViewBuilder content: () -> C) -> some View {
        let p = IslandPresentation(geometry: geometry ?? macBook14.geometry)
        p.mode = .expanded
        let body = content()
        return IslandRootView(presentation: p, compactLeading: { EmptyView() }, compactTrailing: AnyView(EmptyView()),
                              expanded: {
                                  HStack(alignment: .top, spacing: 12) {
                                      MelyStage(pose: pose).updatePill(updateAvailable ? "1.4.0" : nil) {}
                                          .frame(width: 88).padding(.top, 2)
                                      body
                                  }
                              },
                              header: { header(selected: tab, held: held, showsUsage: showsUsage,
                                               updateAvailable: updateAvailable, usage: usage ?? self.usage(.header)) })
            .background(backdrop)
    }

    /// The expanded island's header, as the app builds it (task 7.9).
    public static func header(selected: IslandTabs.Tab, held: Bool = false, showsUsage: Bool = false,
                              updateAvailable: Bool = false, usage: PlanUsageStore? = nil) -> IslandHeader {
        let tabs = IslandTabs()
        tabs.selected = selected
        return IslandHeader(tabs: tabs, items: [
            .init(.sessions, icon: "house.fill", title: "Claude Code"),
            .init(.chat, icon: "bubble.left.fill", title: "Чат"),
            .init(.today, icon: "calendar", title: "Сегодня"),
            .init(.music, icon: "music.note", title: "Музыка"),
            .init(.messages, icon: "bell.fill", title: "Сообщения", badge: 3),
        ], usage: usage ?? self.usage(.header), soundOn: true, heldOpen: held, updateAvailable: updateAvailable,
           showsUsage: showsUsage, toggleSound: {}, openSettings: {}, close: {})
    }

    /// The compact island: Mely (and a cover) left, the status right.
    public static func compact(_ geometry: IslandScreenGeometry, store: SessionStore, usage: PlanUsageStore?,
                               music: NowPlayingModel?, backdrop: Color = Color(white: 0.85)) -> some View {
        let p = IslandPresentation(geometry: geometry)
        p.mode = .compact
        return IslandRootView(presentation: p, compactLeading: { CompactLeading(music: music ?? NowPlayingModel()) },
                              compactTrailing: AnyView(CompactSessionStatus(store: store, usage: usage, music: music)),
                              expanded: { EmptyView() })
            .background(backdrop)
    }

    /// Any preview under the notch.
    public static func peek(_ content: PeekContent, geometry: IslandScreenGeometry? = nil,
                            backdrop: Color = Color(white: 0.85)) -> some View {
        let p = IslandPresentation(geometry: geometry ?? macBook14.geometry)
        p.peek = content
        p.mode = .peek
        p.dismissPeek = {}
        return IslandRootView(presentation: p, compactLeading: { EmptyView() }, compactTrailing: AnyView(EmptyView()),
                              expanded: { EmptyView() })
            .background(backdrop)
    }

    // MARK: Plan limits

    public enum Usage: String, CaseIterable, Sendable {
        /// Nothing yet: no session answered since install.
        case none
        /// What the header snapshots always showed.
        case header
        case normal
        case onlyWeek
        case fiveSpent
        case weekSpent
        /// Last reported two hours ago.
        case stale
    }

    public static func usage(_ sample: Usage) -> PlanUsageStore {
        let suite = "mely-fixtures-usage-\(sample.rawValue)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = PlanUsageStore(defaults: defaults)
        let now = Date().timeIntervalSince1970
        func window(_ percent: Double, _ resetIn: TimeInterval) -> [String: Any] {
            ["used_percentage": percent, "resets_at": now + resetIn]
        }
        let hours = 3600.0, days = 86400.0
        switch sample {
        case .none:
            break
        case .header:
            store.update(rateLimits: ["five_hour": window(56, 2 * hours + 840), "seven_day": window(86, 3 * days + 4 * hours)])
        case .normal:
            store.update(rateLimits: ["five_hour": window(42, 2 * hours + 14 * 60), "seven_day": window(86, 3 * days + 4 * hours)])
        case .onlyWeek:
            store.update(rateLimits: ["seven_day": window(70, 2 * days)])
        case .fiveSpent:
            store.update(rateLimits: ["five_hour": window(100, 80 * 60), "seven_day": window(70, 2 * days)])
        case .weekSpent:
            store.update(rateLimits: ["five_hour": window(10, 4 * hours), "seven_day": window(100, 2 * days + 5 * hours)])
        case .stale:
            store.update(rateLimits: ["five_hour": window(64, 3 * hours), "seven_day": window(91, 5 * days)],
                         now: Date().addingTimeInterval(-2 * hours))
        }
        return store
    }

    // MARK: Sessions

    public static func origin(_ id: String, _ cwd: String, host: String = "com.jetbrains.WebStorm") -> HookOrigin {
        HookOrigin(["session_id": id, "cwd": cwd, "host_bundle_id": host])
    }

    /// `count` sessions working on files.
    public static func sessions(_ count: Int) -> SessionStore {
        let store = SessionStore()
        let names = ["shop", "admin", "api", "docs", "mobile", "billing", "infra"]
        for name in names.prefix(count) {
            store.apply(.toolStarted(tool: "Edit", input: JSONObject(["file_path": "/w/\(name)/index.ts"])),
                        origin: origin(name, "/w/\(name)"))
        }
        return store
    }

    /// Long names and texts everywhere: nothing may push the layout (task 7.10).
    public static func longSessions() -> SessionStore {
        let store = SessionStore()
        let long = origin("a", "/w/очень-длинное-название-проекта-для-проверки-вёрстки-челки")
        store.apply(.userPrompt("x"), origin: long)
        store.apply(.toolStarted(tool: "Bash", input: JSONObject(["command": "npm run build && npm run test -- --coverage --reporter=verbose --runInBand --detectOpenHandles"])), origin: long)
        let other = HookOrigin(["session_id": "b", "cwd": "/w/api", "term_program": "iTerm.app"])
        store.apply(.stop(lastMessage: "Готово: эндпоинт /orders теперь возвращает пагинацию, фильтры по статусу и дате, а ещё я переписал все тесты на новый формат и обновил документацию в README."), origin: other)
        return store
    }

    public static func sessionsPage(_ store: SessionStore, usage: PlanUsageStore? = nil) -> some View {
        ClaudeOverview(store: store, queue: ApprovalQueue(), usage: usage, tabs: IslandTabs(),
                       open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
    }

    /// A WebStorm session asking, with a second request queued behind it.
    public static func requestPage(question: Bool) -> some View {
        let store = SessionStore()
        let queue = ApprovalQueue()
        let ws = origin("a", "/w/shop")
        let event: HookEvent = question
            ? .question(input: JSONObject(["questions": [
                ["question": "Какую библиотеку валидации взять?", "header": "Библиотека", "multiSelect": false,
                 "options": [["label": "zod", "description": "Типы выводятся из схем"],
                             ["label": "yup", "description": "Уже есть в admin"]]],
                ["question": "Что покрыть тестами?", "header": "Тесты", "multiSelect": true,
                 "options": [["label": "Корзину"], ["label": "Оплату"], ["label": "Доставку"]]],
            ]]))
            : .permissionRequest(tool: "Bash", input: JSONObject(["command": "npm run build && npm run test -- --coverage"]),
                                 suggestions: JSONObject(["items": [["type": "addRules"]]]))
        queue.enqueue(event, session: store.apply(event, origin: ws)!, responder: SampleResponder.make())
        let admin = HookOrigin(["session_id": "b", "cwd": "/w/admin", "term_program": "iTerm.app"])
        let second: HookEvent = .permissionRequest(tool: "Edit", input: JSONObject(["file_path": "/w/admin/app.ts"]),
                                                   suggestions: JSONObject([:]))
        queue.enqueue(second, session: store.apply(second, origin: admin)!, responder: SampleResponder.make())
        return ClaudeOverview(store: store, queue: queue, open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
    }

    // MARK: The chat

    public static func chatPreferences() -> ChatPreferences {
        let defaults = UserDefaults(suiteName: "mely-fixtures-chat")!
        defaults.removePersistentDomain(forName: "mely-fixtures-chat")
        let preferences = ChatPreferences(defaults: defaults)
        preferences.claudeFound = true
        return preferences
    }

    public static func conversation(_ transport: ChatTransport = SampleChatTransport(), hasKey: Bool = true) -> ChatConversation {
        ChatConversation(transport: transport, apiKey: { hasKey ? "k" : nil }, model: { .opus })
    }

    /// Sends and lets the answer arrive.
    public static func ask(_ conversation: ChatConversation, _ text: String) async {
        conversation.send(text)
        try? await Task.sleep(for: .milliseconds(150))
    }

    public static func chatPage(_ conversation: ChatConversation, openInClaude: Bool = false) -> some View {
        let tabs = IslandTabs()
        tabs.selected = .chat
        return ClaudeOverview(store: SessionStore(), queue: ApprovalQueue(), tabs: tabs,
                              chat: AnyView(ChatView(conversation: conversation, preferences: chatPreferences(), tabs: tabs,
                                                     openSettings: {}, openInClaude: openInClaude ? {} : nil)),
                              open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
    }

    /// A long answer with every Markdown block.
    public static let longAnswer = """
        ## Почему копейки не сходятся

        Скидка считается **до** округления, а цены позиций — после. На корзине из десяти позиций набегает до пяти копеек.

        1. Округлять цену позиции в `CartItem.total`
        2. Скидку применять к сумме корзины, а не к каждой позиции
        3. Итог округлять один раз, в самом конце

        ```ts
        const total = round(items.reduce((s, i) => s + i.total, 0) * (1 - discount))
        ```

        > Банковское округление здесь не нужно: чеки печатаются с обычным.

        - Проверить на корзине из одной позиции
        - Проверить на корзине со скидкой 100%
        - Проверить возврат части позиций

        Если хотите, могу написать тесты на все три случая и прогнать их на текущих данных корзины.
        """

    // MARK: Calendar, messages, music

    public static func agenda(_ events: Int, long: Bool = false) -> Agenda {
        let now = Date()
        let telemost = MeetingLink(service: .telemost, url: URL(string: "https://telemost.yandex.ru/j/5512")!)
        let titles = ["Стендап", "Синк по корзине", "Интервью фронтенд", "Обед", "Ревью дизайна", "Планирование",
                      "Созвон с партнёрами", "Демо", "Ретро", "1:1", "Разбор инцидента", "Кофе"]
        var today: [CalendarEvent] = [CalendarEvent(id: "d", title: long ? "Дежурство по релизу и разбор всех входящих обращений поддержки за неделю" : "Дежурство по релизу",
                                                    start: now.addingTimeInterval(-600 * 60), end: now.addingTimeInterval(800 * 60),
                                                    isAllDay: true, location: nil, meeting: nil)]
        for i in 0..<events {
            let title = titles[i % titles.count] + (long ? " — очень длинное название встречи, которое не помещается в строку" : "")
            today.append(CalendarEvent(id: "e\(i)", title: title, start: now.addingTimeInterval(Double(i * 50 - 60) * 60),
                                       end: now.addingTimeInterval(Double(i * 50 - 15) * 60), isAllDay: false,
                                       location: i % 3 == 1 ? (long ? "Переговорная «Большая» на седьмом этаже, корпус Б" : "Кафе") : nil,
                                       meeting: i % 3 == 0 ? telemost : nil))
        }
        return Agenda(today: events == 0 ? [] : today, tomorrow: [])
    }

    /// Meetings with a link in 12 and 20 minutes under long dotted names: a known service
    /// and a site Mely does not know.
    public static func soonMeeting() -> Agenda {
        let now = Date()
        let telemost = MeetingLink(service: .telemost, url: URL(string: "https://telemost.yandex.ru/j/5512")!)
        let jitsi = MeetingLink(service: .other, url: URL(string: "https://meet.jit.si/payments-sync")!)
        return Agenda(today: [CalendarEvent(id: "soon", title: "Shared.Пополнение баланса — синк команды платежей и разбор инцидентов",
                                            start: now.addingTimeInterval(12 * 60 + 20), end: now.addingTimeInterval(57 * 60),
                                            isAllDay: false, meeting: telemost),
                              CalendarEvent(id: "link", title: "Shared.Списания — ретро команды платежей за квартал",
                                            start: now.addingTimeInterval(20 * 60 + 20), end: now.addingTimeInterval(65 * 60),
                                            isAllDay: false, meeting: jitsi)],
                      tomorrow: [])
    }

    public static func agendaPage(_ agenda: Agenda?, isOn: Bool = true) -> some View {
        let tabs = IslandTabs()
        tabs.selected = .today
        return ClaudeOverview(store: SessionStore(), queue: ApprovalQueue(), tabs: tabs,
                              today: AnyView(AgendaView(agenda: agenda, isOn: isOn) { _ in }),
                              open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
    }

    public static func messages(_ count: Int, long: Bool = false) -> MirroredMessages {
        let messages = MirroredMessages()
        let now = Date()
        let sample: [(String, String, String)] = [
            ("com.google.Chrome", "Новый заказ", "shop.ru — Заказ №42 оплачен"),
            ("com.anthropic.claudefordesktop", "Claude", "Готов план миграции на Swift 6: три шага…"),
            ("ru.keepcoder.Telegram", "Аня Смирнова", "Созвон переносим на 15:30"),
        ]
        for i in 0..<count {
            let s = sample[i % sample.count]
            let text = long ? s.2 + " — и ещё очень длинный текст сообщения, который не поместится ни в одну, ни в две строки строки уведомления" : s.2
            let title = long ? s.1 + " · рабочий чат команды корзины и оплаты" : s.1
            let n = MirroredNotification(id: Int64(i), bundleId: s.0, title: title, subtitle: nil, body: text,
                                         deliveredAt: now.addingTimeInterval(-Double(count - i) * 300))
            messages.add(n, appName: s.1, title: title, text: text)
        }
        return messages
    }

    public static func messagesPage(_ messages: MirroredMessages) -> some View {
        let tabs = IslandTabs()
        tabs.selected = .messages
        return ClaudeOverview(store: SessionStore(), queue: ApprovalQueue(), tabs: tabs,
                              messages: AnyView(MessagesView(messages: messages) { (_: Int64) in }),
                              open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
    }

    /// A generated cover: a gradient of `size`.
    public static func cover(_ size: NSSize, _ colors: [NSColor] = [.systemPurple, .systemOrange]) -> Data? {
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: colors)?.draw(in: rect, angle: 45)
            return true
        }
        return image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
    }

    public enum Music: String, CaseIterable, Sendable {
        case nothing, track, video, noArtwork
    }

    public static func music(_ sample: Music) -> NowPlayingModel {
        let model = NowPlayingModel()
        switch sample {
        case .nothing:
            break
        case .track:
            model.update(NowPlaying(bundleId: "ru.yandex.desktop.music", parentBundleId: nil, title: "Тёплый вечер",
                                    artist: "Лампа и кот", album: nil, duration: 158, elapsed: 62, timestamp: Date(),
                                    isPlaying: true, rate: 1, artwork: cover(NSSize(width: 200, height: 200)), prohibitsSkip: false))
        case .video:
            model.update(NowPlaying(bundleId: "com.google.Chrome", parentBundleId: nil,
                                    title: "Как устроены часы: полный разбор механизма за 40 минут — от анкера до турбийона",
                                    artist: nil, album: nil, duration: nil, elapsed: 600, timestamp: Date(), isPlaying: true,
                                    rate: 1, artwork: cover(NSSize(width: 480, height: 270), [.systemTeal, .systemIndigo]),
                                    prohibitsSkip: true))
        case .noArtwork:
            model.update(NowPlaying(bundleId: "com.apple.Music", parentBundleId: nil,
                                    title: "Очень длинное название трека из сборника лучших песен за все годы, ремастеринг",
                                    artist: "Оркестр, хор и солисты Большого театра под управлением дирижёра",
                                    album: nil, duration: 3725, elapsed: 3600, timestamp: Date(), isPlaying: false, rate: 0,
                                    artwork: nil, prohibitsSkip: false))
        }
        return model
    }

    /// Previews from the browser silenced, as after a click on its bell.
    public static func peeks() -> NowPlayingPeeks {
        let suite = "mely-fixtures-peeks"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let peeks = NowPlayingPeeks(defaults: defaults)
        peeks.setMuted("com.google.Chrome", true)
        peeks.setMuted("ru.yandex.desktop.music", false)
        return peeks
    }

    public static func musicPage(_ model: NowPlayingModel) -> some View {
        let tabs = IslandTabs()
        tabs.selected = .music
        return ClaudeOverview(store: SessionStore(), queue: ApprovalQueue(), tabs: tabs,
                              music: AnyView(MiniPlayerView(model: model, peeks: peeks(), send: { _ in }, seek: { _ in }, openSource: { _ in })),
                              open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
    }
}

/// A responder nobody listens to, for cards in snapshots.
public enum SampleResponder {
    public static func make() -> HookResponder {
        var fds: [Int32] = [0, 0]
        socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        return HookResponder(fd: fds[0])
    }
}

/// Answers every question with the same Markdown, as a stream would.
public struct SampleChatTransport: ChatTransport {
    public static let answer = """
        Скорее всего, скидка считается **до** округления. Поправить можно так:

        1. Округлять цену позиции в `CartItem.total`
        2. Скидку применять к сумме корзины

        ```ts
        const total = round(items.reduce((s, i) => s + i.total, 0) * (1 - discount))
        ```
        """

    public init() {}

    public func stream(apiKey: String, model: ChatModel, history: [ChatTurn]) -> AsyncThrowingStream<SSEEvent, Error> {
        FixtureChatTransport(answer: Self.answer).stream(apiKey: apiKey, model: model, history: history)
    }
}

/// A chat answer under the test's control: done at once, held open (streaming) until
/// `finish()`, or failed.
public final class FixtureChatTransport: ChatTransport, @unchecked Sendable {
    public enum Ending: Sendable {
        case done
        case held
        case failed(String)
    }

    let answer: String
    let ending: Ending
    private let gate = AsyncStream<Void>.makeStream()

    public init(answer: String, ending: Ending = .done) {
        self.answer = answer
        self.ending = ending
    }

    /// Ends a held answer.
    public func finish() {
        gate.continuation.yield()
        gate.continuation.finish()
    }

    public func stream(apiKey: String, model: ChatModel, history: [ChatTurn]) -> AsyncThrowingStream<SSEEvent, Error> {
        func event(_ obj: [String: Any]) -> SSEEvent {
            SSEEvent(event: obj["type"] as? String ?? "",
                     data: String(decoding: try! JSONSerialization.data(withJSONObject: obj), as: UTF8.self))
        }
        let answer = answer, ending = ending, gate = gate.stream
        return AsyncThrowingStream { c in
            let task = Task {
                c.yield(event(["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": answer]]))
                switch ending {
                case .done:
                    break
                case .held:
                    for await _ in gate { break }
                case .failed(let message):
                    c.finish(throwing: NSError(domain: "fixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
                    return
                }
                c.yield(event(["type": "message_delta", "delta": ["stop_reason": "end_turn"]]))
                c.yield(event(["type": "message_stop"]))
                c.finish()
            }
            c.onTermination = { _ in task.cancel() }
        }
    }
}
