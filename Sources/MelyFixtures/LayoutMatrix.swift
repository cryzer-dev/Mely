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
            let groups: [[LayoutVariant]] = [header(screen), sessions(screen), agents(screen), chat(screen), today(screen), tasks(screen), messages(screen),
                                             music(screen), requests(screen), compact(screen), focus(screen), peeks(screen)]
            return groups.flatMap { $0 }
        }
    }

    static func expanded(_ name: String, _ screen: Fixtures.Screen, _ tab: IslandTabs.Tab,
                         usage: Fixtures.Usage = .header, agents: AgentsModel? = nil, held: Bool = false, showsUsage: Bool = false,
                         updateAvailable: Bool = false, focus: FocusTimer? = nil, then: (@MainActor () -> Void)? = nil,
                         page: @escaping @MainActor () async -> some View) -> LayoutVariant {
        LayoutVariant("\(name)_\(screen.name)", then: then) {
            let content = await page()
            return AnyView(Fixtures.expandedApp(tab, geometry: screen.geometry, held: held, showsUsage: showsUsage,
                                                usage: Fixtures.usage(usage), agents: agents, updateAvailable: updateAvailable,
                                                focus: focus) { content })
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
            // The shortest page: «Обновить» under Mely still fits the island.
            expanded("Header_UpdateEmpty", screen, .sessions, usage: .none, updateAvailable: true) {
                Fixtures.sessionsPage(SessionStore())
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
            // Claude's question after the turn: two lines, unfolded, very long.
            expanded("Sessions_Reply", screen, .sessions) {
                Fixtures.sessionsPage(Fixtures.replySessions(), usage: Fixtures.usage(.normal))
            },
            expanded("Sessions_ReplyOpen", screen, .sessions) {
                Fixtures.sessionsPage(Fixtures.replySessions(), expanded: "a")
            },
            expanded("Sessions_ReplyLongOpen", screen, .sessions) {
                Fixtures.sessionsPage(Fixtures.replySessions(long: true), expanded: "a")
            },
            expanded("Sessions_NoUsageData", screen, .sessions, usage: .none) {
                Fixtures.sessionsPage(Fixtures.sessions(2), usage: Fixtures.usage(.none))
            },
        ]
    }

    /// One agent on, as before; two with the switcher, one of them empty, the other one
    /// asking; the limits card with a block each, Codex pinned; Codex's request.
    static func agents(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        [
            expanded("Agents_One", screen, .sessions, agents: Fixtures.agents([.claude])) {
                Fixtures.sessionsPage(Fixtures.sessions(2), agents: Fixtures.agents([.claude]))
            },
            expanded("Agents_Two", screen, .sessions, agents: Fixtures.agents()) {
                Fixtures.sessionsPage(Fixtures.agentSessions(), agents: Fixtures.agents())
            },
            expanded("Agents_TwoEmpty", screen, .sessions, agents: Fixtures.agents()) {
                Fixtures.sessionsPage(Fixtures.sessions(2), agents: Fixtures.agents(selected: .codex))
            },
            // Under a request, the switcher behind it: the page as it is once the card goes.
            expanded("Agents_WaitingOther", screen, .sessions, agents: Fixtures.agents()) {
                let store = Fixtures.agentSessions()
                let queue = Fixtures.codexWaits(store)
                return SessionsOverview(store: store, agents: Fixtures.agents(), requests: queue.requests,
                                        showsHeader: false, open: { _ in })
            },
            expanded("Request_Codex", screen, .sessions, agents: Fixtures.agents(), held: true) {
                Fixtures.requestPage(question: false, agent: .codex, agents: Fixtures.agents())
            },
            expanded("Request_ClaudeTwoAgents", screen, .sessions, agents: Fixtures.agents(), held: true) {
                Fixtures.requestPage(question: false, agents: Fixtures.agents())
            },
            expanded("Usage_Card_TwoAgents", screen, .sessions, agents: Fixtures.agents(), showsUsage: true) {
                Fixtures.sessionsPage(Fixtures.agentSessions(), agents: Fixtures.agents())
            },
            expanded("Usage_Card_CodexPinned", screen, .sessions, agents: Fixtures.agents(pinned: .codex, codex: false), showsUsage: true) {
                Fixtures.sessionsPage(Fixtures.agentSessions(), agents: Fixtures.agents(pinned: .codex, codex: false))
            },
            LayoutVariant("Compact_CodexPinned_\(screen.name)") {
                AnyView(Fixtures.compact(screen.geometry, store: Fixtures.agentSessions(), usage: nil,
                                         agents: Fixtures.agents(pinned: .codex), music: nil))
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
            // A long name next to both the countdown and «Подключиться».
            expanded("Today_SoonLong", screen, .today) { Fixtures.agendaPage(Fixtures.soonMeeting()) },
            // Today's tasks under the events; alone when the calendar is off.
            expanded("Today_Tasks", screen, .today) { Fixtures.agendaPage(Fixtures.agenda(2), tasks: Fixtures.tasks(.ordinary)) },
            expanded("Today_TasksOnly", screen, .today) { Fixtures.agendaPage(nil, isOn: false, tasks: Fixtures.tasks(.ordinary)) },
            expanded("Today_TasksOnlyEmpty", screen, .today) { Fixtures.agendaPage(nil, isOn: false, tasks: []) },
            expanded("Today_NoEventsTasks", screen, .today) { Fixtures.agendaPage(Fixtures.agenda(0), tasks: Fixtures.tasks(.ordinary)) },
            // Calls at 11 and 13, a task at 12 in the day between them.
            expanded("Today_Mixed", screen, .today) {
                let d = Fixtures.mixedDay()
                return Fixtures.agendaPage(d.agenda, tasks: d.tasks, now: d.now)
            },
            expanded("Today_TasksMore", screen, .today) {
                Fixtures.agendaPage(Fixtures.agenda(1), tasks: Fixtures.tasks(.long) + Fixtures.tasks(.crowded))
            },
            // «Фокус сегодня · 2 ч 10 мин · 4 сессии» on top of each kind of page.
            expanded("Today_Focus", screen, .today) {
                Fixtures.agendaPage(Fixtures.agenda(4), focus: Fixtures.focusRecords([(25, nil), (40, "t3"), (40, nil), (25, nil)]))
            },
            expanded("Today_FocusNone", screen, .today) { Fixtures.agendaPage(Fixtures.agenda(0), focus: []) },
            expanded("Today_FocusOff", screen, .today) { Fixtures.agendaPage(nil, isOn: false, focus: []) },
            expanded("Today_FocusTasks", screen, .today) {
                Fixtures.agendaPage(nil, isOn: false, tasks: Fixtures.tasks(.ordinary), focus: Fixtures.focusRecords([(25, nil)]))
            },
            expanded("Today_FocusOverflow", screen, .today) {
                Fixtures.agendaPage(Fixtures.agenda(12, long: true), tasks: Fixtures.tasks(.ordinary),
                                    focus: Fixtures.focusRecords(Array(repeating: (50, nil), count: 11)))
            },
        ]
    }

    static func tasks(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        [
            expanded("Tasks_Today", screen, .tasks) { Fixtures.tasksPage(Fixtures.tasks(.ordinary)) },
            expanded("Tasks_Spent", screen, .tasks) { Fixtures.tasksPage(Fixtures.tasks(.ordinary), period: .all, focus: Fixtures.tasksFocus()) },
            expanded("Tasks_SpentLong", screen, .tasks) {
                Fixtures.tasksPage(Fixtures.tasks(.long), period: .all, focus: Fixtures.tasksFocus())
            },
            expanded("Tasks_Soon", screen, .tasks) { Fixtures.tasksPage(Fixtures.tasks(.ordinary), period: .soon) },
            expanded("Tasks_All", screen, .tasks) { Fixtures.tasksPage(Fixtures.tasks(.ordinary), period: .all) },
            expanded("Tasks_Empty", screen, .tasks) { Fixtures.tasksPage(Fixtures.tasks(.empty)) },
            expanded("Tasks_DoneOpen", screen, .tasks) { Fixtures.tasksPage(Fixtures.tasks(.ordinary), showsDone: true) },
            expanded("Tasks_AllDone", screen, .tasks) {
                Fixtures.tasksPage(Fixtures.tasks(.ordinary).filter(\.isCompleted))
            },
            expanded("Tasks_Loading", screen, .tasks) { Fixtures.tasksPage([], hasLoaded: false) },
            expanded("Tasks_Long", screen, .tasks) { Fixtures.tasksPage(Fixtures.tasks(.long), period: .all) },
            expanded("Tasks_Editor", screen, .tasks) { Fixtures.tasksPage(Fixtures.tasks(.ordinary), openTask: "t2") },
            expanded("Tasks_EditorLong", screen, .tasks) {
                Fixtures.tasksPage(Fixtures.tasks(.long), period: .all, openTask: "l1")
            },
            // Overflow: long list and tag in the filters, a crowded week, every chip with long text.
            expanded("Tasks_LongFilters", screen, .tasks) {
                Fixtures.tasksPage(Fixtures.tasks(.long), period: .all, listId: "long", tag: "очень-длинный-тег-1")
            },
            expanded("Tasks_Crowded", screen, .tasks) { Fixtures.tasksPage(Fixtures.tasks(.crowded), period: .soon) },
            expanded("Tasks_CrowdedAll", screen, .tasks) { Fixtures.tasksPage(Fixtures.tasks(.crowded), period: .all) },
            expanded("Tasks_LongDoneOpen", screen, .tasks) {
                Fixtures.tasksPage(Fixtures.tasks(.long), period: .all, showsDone: true)
            },
            expanded("Tasks_Deleted", screen, .tasks) {
                Fixtures.tasksPage(Fixtures.tasks(.ordinary),
                                   deleted: "Очень длинное название удалённой задачи, которое не помещается в строку")
            },
            expanded("Tasks_AddLong", screen, .tasks) {
                Fixtures.tasksPage(Fixtures.tasks(.long),
                                   typed: "подготовить квартальный отчёт для совета директоров 12 ноября в 18:30 !!! #работа #очень-длинный-тег-3 #релиз ~3ч",
                                   chosenList: "long")
            },
            expanded("Tasks_Add", screen, .tasks) {
                Fixtures.tasksPage(Fixtures.tasks(.ordinary), typed: "отчёт по релизу в пт !! #работа ~45м")
            },
        ]
    }

    static func messages(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        [
            expanded("Notifications_Empty", screen, .notifications) { Fixtures.messagesPage(Fixtures.messages(0)) },
            expanded("Notifications_Three", screen, .notifications) { Fixtures.messagesPage(Fixtures.messages(3)) },
            expanded("Notifications_Calendar", screen, .notifications) {
                Fixtures.messagesPage(Fixtures.messages(2, calendar: true))
            },
            expanded("Notifications_CalendarLong", screen, .notifications) {
                Fixtures.messagesPage(Fixtures.messages(1, long: true, calendar: true))
            },
            // «×» over the time of the row under the pointer, long title beside it.
            expanded("Notifications_Hover", screen, .notifications) {
                Fixtures.messagesPage(Fixtures.messages(1, long: true, calendar: true), hovered: "cal-moved")
            },
            expanded("Notifications_Overflow", screen, .notifications) { Fixtures.messagesPage(Fixtures.messages(30, long: true)) },
        ]
    }

    static func music(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        Fixtures.Music.allCases.map { sample in
            expanded("Music_\(sample.rawValue)", screen, .music) { Fixtures.musicPage(Fixtures.music(sample)) }
        }
    }

    static func requests(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        [
            expanded("WhatsNew", screen, .sessions) { Fixtures.whatsNewPage() },
            expanded("WhatsNew_NoNotes", screen, .sessions) { Fixtures.whatsNewPage(withNotes: false) },
            expanded("Request_Approval", screen, .sessions, held: true) { Fixtures.requestPage(question: false) },
            expanded("Request_Question", screen, .sessions, held: true) { Fixtures.requestPage(question: true) },
            // Scrolled to the end: the own answer is whole, not lost in the fade.
            expanded("Request_QuestionEnd", screen, .sessions, held: true) { Fixtures.requestPage(question: true, scrolledToEnd: true) },
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

    /// The timer left, around Mely, in place of the cover; a waiting request right. The card
    /// under Mely, with and without a task, on the shortest page, above «Обновить».
    static func focus(_ screen: Fixtures.Screen) -> [LayoutVariant] {
        let wings: [(String, Fixtures.Focus)] = [("Working", .working), ("Break", .onBreak), ("Paused", .paused)]
        return wings.map { name, phase in
            LayoutVariant("Focus_Wing_\(name)_\(screen.name)") {
                AnyView(Fixtures.compact(screen.geometry, store: Fixtures.sessions(1), usage: Fixtures.usage(.normal),
                                         music: Fixtures.music(.track), focus: Fixtures.focus(phase)))
            }
        } + [
            LayoutVariant("Focus_Wing_Request_\(screen.name)") {
                AnyView(Fixtures.compact(screen.geometry, store: Fixtures.waitingSessions(), usage: nil, music: nil,
                                         focus: Fixtures.focus(.working)))
            },
        ] + Fixtures.Focus.allCases.map { phase in
            expanded("Focus_Card_\(phase.rawValue)", screen, .sessions, focus: Fixtures.focus(phase)) {
                Fixtures.sessionsPage(Fixtures.sessions(1))
            }
        } + [
            expanded("Focus_Card_NoTask", screen, .sessions, focus: Fixtures.focus(.working, task: nil)) {
                Fixtures.sessionsPage(Fixtures.sessions(1))
            },
            expanded("Focus_Card_LongTask", screen, .sessions,
                     focus: Fixtures.focus(.paused, task: "Подготовить квартальный отчёт для совета директоров и разослать")) {
                Fixtures.sessionsPage(Fixtures.sessions(1))
            },
            // The shortest page: the card and «Обновить» under it still fit the island.
            expanded("Focus_Card_Update", screen, .sessions, usage: .none, updateAvailable: true, focus: Fixtures.focus(.working)) {
                Fixtures.sessionsPage(SessionStore())
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
            // A dotted name with no spaces to break at: «Подключиться» once gave way to it.
            ("ReminderDotted", PeekContent(id: "rd", symbol: "video.fill", tint: .green,
                                           title: "Shared.Пополнение баланса — синк команды платежей",
                                           subtitle: "Встреча в Телемосте", appBundleId: "ru.yandex.desktop.telemost",
                                           actionTitle: "Подключиться", until: Date().addingTimeInterval(4 * 60 + 20))),
            ("ReminderLink", PeekContent(id: "rl", symbol: "video.fill", tint: .green,
                                         title: "Shared.Пополнение баланса — синк команды платежей",
                                         subtitle: "Встреча · meet.jit.si",
                                         actionTitle: "Подключиться", until: Date().addingTimeInterval(4 * 60 + 20))),
            ("Cancelled", PeekContent(id: "event-cancelled-g", symbol: "calendar.badge.minus", tint: .red,
                                      title: "Отменено: 14:00",
                                      subtitle: "Shared.Пополнение баланса — синк команды платежей и разбор инцидентов")),
            ("Telemetry", PeekContent(id: "telemetry-notice", symbol: "chart.bar.fill", tint: .blue,
                                      title: "Помогите улучшить Mely",
                                      subtitle: "Mely анонимно считает, какими функциями пользуются чаще", actionTitle: "Отключить")),
            ("Updated", PeekContent(id: "updated-1.3.0", symbol: "sparkles", tint: .green, title: "Обновилась до 1.3.0",
                                    subtitle: "Посмотрите, что изменилось", actionTitle: "Что нового")),
            // A task's due reminder: «+1 ч» and «Готово», «×»; a long name gives way to them.
            ("TaskDue", PeekContent(id: "task-due-t", symbol: "checklist", tint: .blue,
                                    title: "Созвон с бухгалтером по поводу квартальной отчётности и налогов",
                                    subtitle: "15:00–15:30 · ~30 мин · Работа", actionTitle: "Готово", secondaryActionTitle: "+1 ч",
                                    staysUntil: Date().addingTimeInterval(600), yieldsToLasting: true)),
            ("TaskDueShort", PeekContent(id: "task-due-s", symbol: "checklist", tint: .blue, title: "Купить корм",
                                         subtitle: "в 18:00 · Дом", actionTitle: "Готово", secondaryActionTitle: "+1 ч",
                                         staysUntil: Date().addingTimeInterval(600), yieldsToLasting: true)),
            // The focus: three buttons with a task («Ещё 10 мин» folds into «⋯»), two without.
            ("FocusDone", FocusPeeks.finished(worked: 40 * 60, task: "Отчёт по релизу")),
            ("FocusDoneLong", FocusPeeks.finished(worked: 75 * 60,
                                                  task: "Подготовить квартальный отчёт для совета директоров и разослать всем")),
            ("FocusDoneNoTask", FocusPeeks.finished(worked: 25 * 60, task: nil)),
            ("FocusBreak", FocusPeeks.breakStarted(length: 15 * 60, worked: 50 * 60)),
            ("FocusBreakOver", FocusPeeks.breakOver(duration: 40 * 60, task: "Подготовить квартальный отчёт для совета директоров")),
            ("FocusAway", FocusPeeks.away(7 * 60)),
            ("FocusMeeting", FocusPeeks.meeting(FocusMeeting(id: "g", title: "Shared.Пополнение баланса — синк команды платежей",
                                                             start: Date().addingTimeInterval(5 * 60)))),
            ("FocusHeld", FocusPeeks.held(23)),
            ("Message", PeekContent(id: "m", symbol: "bell.fill", tint: .blue, title: "Аня Смирнова",
                                    subtitle: "Созвон переносим на 15:30, ссылку кину в чат. Если не получится, давай завтра утром до стендапа, я весь день на встречах",
                                    appBundleId: "ru.keepcoder.Telegram", opensApp: true)),
        ]
        return samples.map { name, content in
            LayoutVariant("Peek_\(name)_\(screen.name)") { AnyView(Fixtures.peek(content, geometry: screen.geometry)) }
        }
    }
}
