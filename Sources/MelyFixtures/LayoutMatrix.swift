import SwiftUI
import MelyCore
import MelyUI

/// One state of the island to lay out and check (openspec island-layout).
public struct LayoutVariant {
    /// `<page>_<screen>_<data>`: names the PNG in `mely-snapshots --matrix` and the failure.
    public let name: String
    public let build: @MainActor () async -> AnyView
    /// Run after the first layout, before the checks (an answer finishing, say).
    public let then: (@MainActor () -> Void)?

    public init(_ name: String, then: (@MainActor () -> Void)? = nil, build: @escaping @MainActor () async -> AnyView) {
        self.name = name
        self.build = build
        self.then = then
    }
}

/// Every page, the header, the compact island and the previews, on each screen, with
/// empty, ordinary, overflowing and long data.
@MainActor
public enum LayoutMatrix {
    public static var all: [LayoutVariant] {
        Fixtures.screens.flatMap { screen -> [LayoutVariant] in
            let groups: [[LayoutVariant]] = [header(screen), sessions(screen), chat(screen), today(screen), messages(screen),
                                             music(screen), requests(screen), compact(screen), peeks(screen)]
            return groups.flatMap { $0 }
        }
    }

    static func expanded(_ name: String, _ screen: Fixtures.Screen, _ tab: IslandTabs.Tab,
                         usage: Fixtures.Usage = .header, held: Bool = false, showsUsage: Bool = false,
                         updateAvailable: Bool = false, then: (@MainActor () -> Void)? = nil,
                         page: @escaping @MainActor () async -> some View) -> LayoutVariant {
        LayoutVariant("\(name)_\(screen.name)", then: then) {
            let content = await page()
            return AnyView(Fixtures.expandedApp(tab, geometry: screen.geometry, held: held, showsUsage: showsUsage,
                                                usage: Fixtures.usage(usage), updateAvailable: updateAvailable) { content })
        }
    }

    static func header(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        Fixtures.Usage.allCases.flatMap { usage in
            [expanded("Header_\(usage.rawValue)", screen, .sessions, usage: usage) { Fixtures.sessionsPage(Fixtures.sessions(1)) },
             expanded("HeaderCard_\(usage.rawValue)", screen, .sessions, usage: usage, showsUsage: true) {
                 Fixtures.sessionsPage(Fixtures.sessions(1))
             }]
        } + [
            expanded("Header_HeldUpdate", screen, .sessions, held: true, updateAvailable: true) {
                Fixtures.sessionsPage(Fixtures.sessions(1))
            },
        ]
    }

    static func sessions(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        [
            expanded("Sessions_Empty", screen, .sessions, usage: .none) { Fixtures.sessionsPage(SessionStore()) },
            expanded("Sessions_EmptyUsage", screen, .sessions) {
                Fixtures.sessionsPage(SessionStore(), usage: Fixtures.usage(.normal))
            },
            expanded("Sessions_One", screen, .sessions) { Fixtures.sessionsPage(Fixtures.sessions(1), usage: Fixtures.usage(.normal)) },
            expanded("Sessions_Seven", screen, .sessions) { Fixtures.sessionsPage(Fixtures.sessions(7), usage: Fixtures.usage(.normal)) },
            expanded("Sessions_Long", screen, .sessions) { Fixtures.sessionsPage(Fixtures.longSessions(), usage: Fixtures.usage(.normal)) },
            expanded("Sessions_StaleUsage", screen, .sessions, usage: .stale) {
                Fixtures.sessionsPage(Fixtures.sessions(2), usage: Fixtures.usage(.stale))
            },
            expanded("Sessions_NoUsageData", screen, .sessions, usage: .none) {
                Fixtures.sessionsPage(Fixtures.sessions(2), usage: Fixtures.usage(.none))
            },
        ]
    }

    static func chat(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        // Built once per variant: each needs its own conversation.
        func page(_ make: @escaping @MainActor () async -> ChatConversation, openInClaude: Bool = false) -> @MainActor () async -> AnyView {
            { AnyView(Fixtures.chatPage(await make(), openInClaude: openInClaude)) }
        }
        let held = FixtureChatTransport(answer: Fixtures.longAnswer, ending: .held)
        return [
            expanded("Chat_Empty", screen, .chat, page: page { Fixtures.conversation() }),
            expanded("Chat_NoKey", screen, .chat, page: page { Fixtures.conversation(hasKey: false) }),
            // Issue #3: one short message and a short answer, nothing scrolled.
            expanded("Chat_FirstMessage", screen, .chat, page: page({
                let c = Fixtures.conversation(FixtureChatTransport(answer: "Привет! Похоже, это проверка связи. Всё работает. Чем помочь?"))
                await Fixtures.ask(c, "123")
                return c
            }, openInClaude: true)),
            expanded("Chat_Answer", screen, .chat, page: page {
                let c = Fixtures.conversation()
                c.offer(context: ChatContext(appName: "Safari", windowTitle: "Корзина — shop", url: "https://shop.example.ru/cart"))
                await Fixtures.ask(c, "Почему в корзине копейки не сходятся?")
                return c
            }),
            expanded("Chat_Streaming", screen, .chat, page: page {
                let c = Fixtures.conversation(FixtureChatTransport(answer: Fixtures.longAnswer, ending: .held))
                await Fixtures.ask(c, "Почему в корзине копейки не сходятся?")
                return c
            }),
            // The answer finishes after the first layout: plain text turns into taller Markdown.
            expanded("Chat_LongAnswerDone", screen, .chat, then: { held.finish() }, page: page({
                let c = Fixtures.conversation(held)
                await Fixtures.ask(c, "Почему в корзине копейки не сходятся?")
                return c
            }, openInClaude: true)),
            expanded("Chat_Failed", screen, .chat, page: page {
                let c = Fixtures.conversation(FixtureChatTransport(answer: "", ending: .failed(
                    "Claude Code не ответил за минуту. Проверьте, что он установлен и вы вошли в аккаунт, и попробуйте ещё раз.")))
                await Fixtures.ask(c, "Почему в корзине копейки не сходятся?")
                return c
            }),
            expanded("Chat_Attachments", screen, .chat, page: page({
                let c = Fixtures.conversation()
                c.offer(context: ChatContext(appName: "Safari", windowTitle: "Очень длинный заголовок вкладки браузера про корзину магазина — shop",
                                             url: "https://shop.example.ru/cart"))
                let dir = FileManager.default.temporaryDirectory
                let files = ["Снимок экрана 2026-10-22 в 11.40.15 очень длинное имя.png", "Отчёт по корзине за третий квартал.pdf"]
                    .map { dir.appendingPathComponent($0) }
                for file in files { try? Data([0x89, 0x50, 0x4E, 0x47]).write(to: file) }
                c.attach(files)
                return c
            }, openInClaude: true)),
            // The fullest footer: a new conversation, two files, «Открыть в Claude», the model.
            expanded("Chat_FullFooter", screen, .chat, page: page({
                let c = Fixtures.conversation(FixtureChatTransport(answer: "Готово."))
                await Fixtures.ask(c, "Привет")
                let dir = FileManager.default.temporaryDirectory
                let files = ["Снимок экрана 2026-10-22 в 11.40.15 очень длинное имя.png", "Отчёт по корзине за третий квартал.pdf"]
                    .map { dir.appendingPathComponent($0) }
                for file in files { try? Data([0x89, 0x50, 0x4E, 0x47]).write(to: file) }
                c.attach(files)
                return c
            }, openInClaude: true)),
            expanded("Chat_Long", screen, .chat, page: page({
                let c = Fixtures.conversation(FixtureChatTransport(answer: Fixtures.longAnswer))
                await Fixtures.ask(c, "Почему в корзине копейки не сходятся?")
                await Fixtures.ask(c, "А если скидка задана в рублях, а не в процентах, и действует только на часть позиций корзины?")
                return c
            }, openInClaude: true)),
        ]
    }

    static func today(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        [
            expanded("Today_Off", screen, .today) { Fixtures.agendaPage(nil, isOn: false) },
            expanded("Today_NoAccess", screen, .today) { Fixtures.agendaPage(nil) },
            expanded("Today_Empty", screen, .today) { Fixtures.agendaPage(Fixtures.agenda(0)) },
            expanded("Today_Five", screen, .today) { Fixtures.agendaPage(Fixtures.agenda(4)) },
            expanded("Today_Overflow", screen, .today) { Fixtures.agendaPage(Fixtures.agenda(12, long: true)) },
        ]
    }

    static func messages(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        [
            expanded("Messages_Empty", screen, .messages) { Fixtures.messagesPage(Fixtures.messages(0)) },
            expanded("Messages_Three", screen, .messages) { Fixtures.messagesPage(Fixtures.messages(3)) },
            expanded("Messages_Overflow", screen, .messages) { Fixtures.messagesPage(Fixtures.messages(30, long: true)) },
        ]
    }

    static func music(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        Fixtures.Music.allCases.map { sample in
            expanded("Music_\(sample.rawValue)", screen, .music) { Fixtures.musicPage(Fixtures.music(sample)) }
        }
    }

    static func requests(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        [
            expanded("Request_Approval", screen, .sessions, held: true) { Fixtures.requestPage(question: false) },
            expanded("Request_Question", screen, .sessions, held: true) { Fixtures.requestPage(question: true) },
        ]
    }

    static func compact(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        [
            LayoutVariant("Compact_Idle_\(screen.name)") {
                AnyView(Fixtures.compact(screen.geometry, store: SessionStore(), usage: nil, music: nil))
            },
            LayoutVariant("Compact_NoUsageData_\(screen.name)") {
                AnyView(Fixtures.compact(screen.geometry, store: Fixtures.longSessions(), usage: Fixtures.usage(.none), music: nil))
            },
            LayoutVariant("Compact_MusicUsage_\(screen.name)") {
                AnyView(Fixtures.compact(screen.geometry, store: Fixtures.sessions(1), usage: Fixtures.usage(.normal),
                                         music: Fixtures.music(.track)))
            },
            LayoutVariant("Compact_Spent_\(screen.name)") {
                AnyView(Fixtures.compact(screen.geometry, store: Fixtures.sessions(1), usage: Fixtures.usage(.weekSpent),
                                         music: Fixtures.music(.video)))
            },
        ]
    }

    static func peeks(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        let samples: [(String, PeekContent)] = [
            ("Finished", PeekContent(id: "x", symbol: "checkmark", tint: .green, title: "Готово · shop",
                                     subtitle: "Корзина пересчитывает скидки, тесты зелёные.", appBundleId: "com.jetbrains.WebStorm")),
            ("Reminder", PeekContent(id: "r", symbol: "video.fill", tint: .green,
                                     title: "Синк по релизу и планирование следующего спринта со всей командой",
                                     subtitle: "Встреча в Телемосте", appBundleId: "ru.yandex.desktop.telemost",
                                     actionTitle: "Подключиться", until: Date().addingTimeInterval(4 * 60 + 20))),
            ("Message", PeekContent(id: "m", symbol: "bell.fill", tint: .blue, title: "Аня Смирнова",
                                    subtitle: "Созвон переносим на 15:30, ссылку кину в чат. Если не получится, давай завтра утром до стендапа, я весь день на встречах",
                                    appBundleId: "ru.keepcoder.Telegram", opensApp: true)),
        ]
        return samples.map { name, content in
            LayoutVariant("Peek_\(name)_\(screen.name)") { AnyView(Fixtures.peek(content, geometry: screen.geometry)) }
        }
    }
}
