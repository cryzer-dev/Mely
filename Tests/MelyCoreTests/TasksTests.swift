import Testing
import Foundation
@testable import MelyCore

@Suite struct TasksTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return c
    }()
    /// Tuesday 2026-10-27, `h` hours in; `d` days later.
    func at(_ h: Double, plusDays d: Int = 0) -> Date {
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 27 + d))!
        return day.addingTimeInterval(h * 3600)
    }
    func day(_ d: Int) -> TaskDue { .day(of: at(0, plusDays: d), calendar: cal) }
    func task(_ title: String, _ due: TaskDue? = nil, _ priority: TaskPriority = .none, tags: [String] = [],
              estimate: TaskEstimate? = nil, list: String = "work", done: Date? = nil) -> TaskItem {
        TaskItem(id: title, title: title, due: due, priority: priority, marks: TaskMarks(tags: tags, estimate: estimate),
                 listId: list, listTitle: list, completedAt: done)
    }
    func titles(_ board: TaskBoard) -> [[String]] { board.groups.map { $0.items.map(\.title) } }

    // MARK: 2.1 Priority and due

    @Test func priorityFromEventKit() {
        #expect(TaskPriority(eventKit: 0) == .none)
        #expect((1...4).allSatisfy { TaskPriority(eventKit: $0) == .high })
        #expect(TaskPriority(eventKit: 5) == .medium)
        #expect((6...9).allSatisfy { TaskPriority(eventKit: $0) == .low })
        #expect(TaskPriority(eventKit: 12) == .none)
        #expect(TaskPriority.allCases.map(\.eventKitValue) == [0, 9, 5, 1])
        #expect(TaskPriority.allCases.map { TaskPriority(eventKit: $0.eventKitValue) } == TaskPriority.allCases)
        #expect(TaskPriority.high.marks == "!!!")
        #expect(TaskPriority.none.marks == "")
    }

    @Test func dueFromComponents() {
        let dayOnly = TaskDue(components: DateComponents(year: 2026, month: 10, day: 30), calendar: cal)
        #expect(dayOnly == .day(year: 2026, month: 10, day: 30))
        let timed = TaskDue(components: DateComponents(year: 2026, month: 10, day: 27, hour: 15, minute: 0), calendar: cal)
        #expect(timed == .time(at(15)))
        #expect(timed?.components(calendar: cal).hour == 15)
        #expect(dayOnly?.components(calendar: cal).hour == nil)
    }

    @Test func overdue() {
        let now = at(12)
        #expect(day(-1).isOverdue(now: now, calendar: cal))
        #expect(!day(0).isOverdue(now: now, calendar: cal))         // today, no time: not overdue all day
        #expect(TaskDue.time(at(11)).isOverdue(now: now, calendar: cal))
        #expect(!TaskDue.time(at(13)).isOverdue(now: now, calendar: cal))
    }

    @Test func movingKeepsTheTime() {
        #expect(TaskDue.time(at(15)).moved(toDayOf: at(10, plusDays: 1), calendar: cal) == .time(at(15, plusDays: 1)))
        #expect(day(-3).moved(toDayOf: at(10), calendar: cal) == day(0))
    }

    // MARK: 2.2 Marks in the notes

    @Test func writeIntoEmptyNotes() {
        #expect(TaskMarks.write(TaskMarks(tags: ["работа", "релиз"]), into: nil) == "#работа #релиз")
        #expect(TaskMarks.write(TaskMarks(tags: ["работа"], estimate: .overHour), into: "") == "#работа · ~1 ч+")
        #expect(TaskMarks.write(TaskMarks(estimate: .m45), into: nil) == "~45 мин")
        #expect(TaskMarks.write(TaskMarks(), into: nil) == nil)
    }

    @Test func userTextIsKept() {
        let notes = "Номер договора 123"
        #expect(TaskMarks.write(TaskMarks(estimate: .m15), into: notes) == "Номер договора 123\n~15 мин")
        let marked = "Номер договора 123\n#финансы"
        #expect(TaskMarks.parse(notes: marked).body == "Номер договора 123")
        #expect(TaskMarks.parse(notes: marked).marks.tags == ["финансы"])
        // Replacing the line, then removing the last mark.
        #expect(TaskMarks.write(TaskMarks(tags: ["финансы"], estimate: .h1), into: marked) == "Номер договора 123\n#финансы · ~1 ч")
        #expect(TaskMarks.write(TaskMarks(), into: marked) == "Номер договора 123")
        #expect(TaskMarks.write(TaskMarks(), into: "#финансы") == nil)
    }

    @Test func readsHandWrittenEstimates() {
        func estimate(_ line: String) -> TaskEstimate? { TaskMarks.parse(notes: line).marks.estimate }
        #expect(estimate("~1ч") == .h1)
        #expect(estimate("~45м") == .m45)
        #expect(estimate("~20 мин") == .m30)
        #expect(estimate("~2 ч") == .overHour)
        #expect(estimate("~2 часа") == .overHour)
        #expect(estimate("~1,5ч") == .overHour)
        #expect(estimate("~1 ч 30 мин") == .overHour)
        #expect(estimate("~1 ч+") == .overHour)
        #expect(estimate("#работа · ~30 мин") == .m30)
        // Written back in the canonical form.
        let read = TaskMarks.parse(notes: "#работа ~40м").marks
        #expect(TaskMarks.write(read, into: nil) == "#работа · ~45 мин")
    }

    @Test func notMarks() {
        for notes in ["обсудить #релиз с командой", "#работа ~", "~3", "купить ~3 яблока", "#работа · ~30 мин потом", "·"] {
            let parsed = TaskMarks.parse(notes: notes)
            #expect(parsed.marks.isEmpty, "\(notes)")
            #expect(parsed.body == notes)
        }
        // A marks-like line in the middle is text; only the last line counts.
        let middle = "#работа\nпозвонить после обеда"
        #expect(TaskMarks.parse(notes: middle).marks.isEmpty)
    }

    @Test func estimateScaleAndSums() {
        #expect(TaskEstimate(minutes: 0) == nil)
        #expect([5, 15, 16, 30, 31, 45, 46, 60, 61, 180].map { TaskEstimate(minutes: $0)! } ==
                [.m15, .m15, .m30, .m30, .m45, .m45, .h1, .h1, .overHour, .overHour])
        #expect(TaskEstimate.allCases.map(\.label) == ["~15 мин", "~30 мин", "~45 мин", "~1 ч", "1 ч+"])
        #expect(TaskEstimate.format(totalMinutes: 45) == "45 мин")
        #expect(TaskEstimate.format(totalMinutes: 60) == "1 ч")
        #expect(TaskEstimate.format(totalMinutes: 150) == "2 ч 30 мин")
    }

    // MARK: 2.3 Board

    @Test func todayScenario() {
        let items = [task("Купить корм", day(0)), task("Созвон с бухгалтером", .time(at(15)), .high),
                     task("Оплатить интернет", day(-2)), task("Через неделю", day(7))]
        let board = TaskBoard.make(items: items, filter: TaskFilter(period: .today), now: at(11), calendar: cal)
        #expect(board.groups.map(\.title) == ["Просрочено", "Сегодня"])
        #expect(titles(board) == [["Оплатить интернет"], ["Созвон с бухгалтером", "Купить корм"]])
    }

    @Test func priorityOrdersSameDue() {
        let items = [task("Б", day(0)), task("А", day(0), .low), task("В", day(0), .high), task("Г", .time(at(9)))]
        let board = TaskBoard.make(items: items, filter: TaskFilter(), now: at(8), calendar: cal)
        #expect(titles(board) == [["Г", "В", "А", "Б"]])
    }

    @Test func soonScenario() {
        let items = [task("Сегодня", day(0)), task("Завтра", day(1)), task("Через 10 дней", day(10)), task("Без даты")]
        let board = TaskBoard.make(items: items, filter: TaskFilter(period: .soon), now: at(10), calendar: cal)
        #expect(board.groups.map(\.title) == ["Сегодня", "Завтра"])
        let week = TaskBoard.make(items: [task("Чт", day(2)), task("Через 7", day(7)), task("Через 8", day(8))],
                                  filter: TaskFilter(period: .soon), now: at(10), calendar: cal)
        #expect(week.groups.map(\.title) == ["Чт, 29 окт", "Вт, 3 ноя"])
    }

    @Test func allWithUndated() {
        let items = [task("Без даты", nil, .high), task("Потом", day(30)), task("Сегодня", day(0)), task("Давно", day(-5))]
        let board = TaskBoard.make(items: items, filter: TaskFilter(period: .all), now: at(10), calendar: cal)
        #expect(board.groups.map(\.title) == ["Просрочено", "Сегодня", "Чт, 26 ноя", "Без срока"])
        #expect(board.groups.last?.load == nil)
        let limited = TaskBoard.make(items: items, filter: TaskFilter(period: .all), now: at(10), calendar: cal, limit: 2)
        #expect(titles(limited) == [["Давно"], ["Сегодня"]])
        #expect(limited.hiddenCount == 2)
    }

    @Test func listAndTagFilter() {
        let items = [task("Работа", day(0), tags: ["Работа"]), task("Дом", day(0), tags: ["дом"], list: "home"),
                     task("Тоже работа", day(0), tags: ["работа", "срочно"], list: "home")]
        let byTag = TaskBoard.make(items: items, filter: TaskFilter(tag: "работа"), now: at(10), calendar: cal)
        #expect(titles(byTag) == [["Работа", "Тоже работа"]])
        let byList = TaskBoard.make(items: items, filter: TaskFilter(listId: "home"), now: at(10), calendar: cal)
        #expect(titles(byList) == [["Дом", "Тоже работа"]])
        let both = TaskBoard.make(items: items, filter: TaskFilter(listId: "home", tag: "срочно"), now: at(10), calendar: cal)
        #expect(titles(both) == [["Тоже работа"]])
    }

    @Test func empty() {
        let board = TaskBoard.make(items: [task("Завтра", day(1)), task("Без даты")], filter: TaskFilter(), now: at(10), calendar: cal)
        #expect(board.isEmpty)
    }

    @Test func doneTodayStaysAtTheEnd() {
        let items = [task("Сделано", day(0), .high, done: at(9)), task("Осталось", day(0)),
                     task("Вчерашнее", day(-1), done: at(18, plusDays: -1))]
        let board = TaskBoard.make(items: items, filter: TaskFilter(), now: at(10), calendar: cal)
        #expect(titles(board) == [["Осталось", "Сделано"]])
    }

    @Test func daySum() {
        let items = [task("a", day(0), estimate: .m30), task("b", day(0), estimate: .h1), task("c", day(0), estimate: .h1), task("d", day(0))]
        let board = TaskBoard.make(items: items, filter: TaskFilter(), now: at(10), calendar: cal)
        #expect(board.groups.first?.load?.text == "~2 ч 30 мин · +1 без оценки")
        let big = TaskBoard.make(items: [task("a", day(0), estimate: .m30), task("b", day(0), estimate: .overHour)],
                                 filter: TaskFilter(), now: at(10), calendar: cal)
        #expect(big.groups.first?.load?.text == "от ~1 ч 30 мин")
        // Done ones leave the sum.
        let done = TaskBoard.make(items: [task("a", day(0), estimate: .m30), task("b", day(0), estimate: .h1, done: at(9)),
                                          task("c", day(0), estimate: .h1)],
                                  filter: TaskFilter(), now: at(10), calendar: cal)
        #expect(done.groups.first?.load?.text == "~1 ч 30 мин")
        let none = TaskBoard.make(items: [task("a", day(0))], filter: TaskFilter(), now: at(10), calendar: cal)
        #expect(none.groups.first?.load == nil)
    }

    @Test func dayRollsOver() {
        let items = [task("Сегодня", day(0)), task("Завтра", day(1))]
        let tonight = TaskBoard.make(items: items, filter: TaskFilter(), now: at(23.9), calendar: cal)
        #expect(titles(tonight) == [["Сегодня"]])
        let morning = TaskBoard.make(items: items, filter: TaskFilter(), now: at(8, plusDays: 1), calendar: cal)
        #expect(morning.groups.map(\.title) == ["Просрочено", "Сегодня"])
        #expect(titles(morning) == [["Сегодня"], ["Завтра"]])
    }

    @Test func todaySummaryShowsMore() {
        let items = (1...8).map { task("Задача \($0)", day(0), estimate: .m15) }
        let summary = TaskBoard.todaySummary(items: items, now: at(10), calendar: cal)
        #expect(summary.items.count == 5)
        #expect(summary.more == 3)
        #expect(summary.load?.text == "~2 ч")
    }

    // MARK: 2.4 Settings

    @MainActor @Test func deletedListFallsBack() throws {
        let defaults = try #require(UserDefaults(suiteName: "TasksTests-\(UUID().uuidString)"))
        let settings = TaskSettings(defaults: defaults)
        #expect(settings.showsInToday && settings.remindsUnderNotch && settings.filter == TaskFilter())
        settings.newTaskList = "mely"
        settings.filter = TaskFilter(period: .soon, tag: "работа")
        #expect(settings.listForNewTasks(available: ["inbox", "mely"], defaultList: "inbox") == "mely")
        #expect(settings.listForNewTasks(available: ["inbox"], defaultList: "inbox") == "inbox")
        let reloaded = TaskSettings(defaults: defaults)
        #expect(reloaded.newTaskList == "mely")
        #expect(reloaded.filter == TaskFilter(period: .soon, tag: "работа"))
    }

    // MARK: 2.5 Due reminders

    @Test func dueReminderOnce() {
        var schedule = TaskReminderSchedule()
        let item = task("Созвон", .time(at(15)))
        #expect(schedule.due([item], now: at(14.9)).isEmpty)
        #expect(schedule.due([item], now: at(15)).map(\.title) == ["Созвон"])
        #expect(schedule.due([item], now: at(15.1)).isEmpty)
        // «+1 ч»: a new due time is announced again.
        var moved = item
        moved.due = .time(at(16))
        #expect(schedule.due([moved], now: at(16)).map(\.title) == ["Созвон"])
        // No time, done: never.
        #expect(schedule.due([task("День", day(0)), task("Готово", .time(at(15.5)), done: at(15))], now: at(15.6)).isEmpty)
    }

    @Test func missedWhileAsleep() {
        var schedule = TaskReminderSchedule()
        #expect(schedule.due([task("Недавно", .time(at(15)))], now: at(15.9)).count == 1)
        #expect(schedule.due([task("Давно", .time(at(13)))], now: at(15.9)).isEmpty)
    }
}
