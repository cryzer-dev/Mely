import Testing
import Foundation
@testable import MelyCore

@Suite struct QuickTaskParserTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return c
    }()
    /// Tuesday 2026-10-27, `h` hours in; `d` days later.
    func at(_ h: Double, plusDays d: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: 27 + d))!.addingTimeInterval(h * 3600)
    }
    func day(_ d: Int) -> TaskDue { .day(of: at(0, plusDays: d), calendar: cal) }
    func parse(_ text: String, now: Double = 12) -> QuickTask { QuickTaskParser.parse(text, now: at(now), calendar: cal) }

    // MARK: 3.1 Parsing

    @Test func dayAndTime() {
        let t = parse("позвонить в банк завтра в 10")
        #expect(t.title == "Позвонить в банк")
        #expect(t.due == .time(at(10, plusDays: 1)))
    }

    @Test func everythingAtOnce() {
        let t = parse("отчёт по релизу в пт !! #работа ~45м")
        #expect(t.title == "Отчёт по релизу")
        #expect(t.due == day(3))                        // Tuesday → Friday
        #expect(t.priority == .medium)
        #expect(t.tags == ["работа"])
        #expect(t.estimate == .m45)
    }

    @Test func noDue() {
        let t = parse("прочитать статью про EventKit")
        #expect(t == QuickTask(title: "Прочитать статью про EventKit"))
    }

    @Test func pastHourMeansEvening() {
        #expect(parse("выпить таблетку в 9", now: 18).due == .time(at(21)))
        #expect(parse("выпить таблетку в 9", now: 8).due == .time(at(9)))
        // Both 9:00 and 21:00 gone: tomorrow morning.
        #expect(parse("выпить таблетку в 9", now: 22).due == .time(at(9, plusDays: 1)))
        #expect(parse("в 9 утра зарядка", now: 18).due == .time(at(9, plusDays: 1)))
        #expect(parse("ужин в 7 вечера", now: 12).due == .time(at(19)))
        #expect(parse("в 3 дня созвон", now: 10).due == .time(at(15)))
        #expect(parse("в 21 позвонить", now: 10).due == .time(at(21)))
        #expect(parse("встреча в 10:30", now: 9).due == .time(at(10.5)))
        #expect(parse("встреча 15:30", now: 9).due == .time(at(15.5)))
    }

    @Test func dayWords() {
        #expect(parse("купить корм сегодня").due == day(0))
        #expect(parse("купить корм на завтра").due == day(1))
        #expect(parse("послезавтра купить корм").due == day(2))
        #expect(parse("купить корм сегодня").title == "Купить корм")
    }

    @Test func weekdays() {
        #expect(parse("в пятницу отчёт").due == day(3))
        #expect(parse("во вторник отчёт").due == day(7))   // today is Tuesday: next week
        #expect(parse("в пн созвон").due == day(6))
        #expect(parse("в вс отдых").due == day(5))
        #expect(parse("в среду в 11 дейли").due == .time(at(11, plusDays: 1)))
    }

    @Test func dates() {
        #expect(parse("продлить страховку 12.11").due == .day(year: 2026, month: 11, day: 12))
        #expect(parse("продлить страховку 12 ноября").due == .day(year: 2026, month: 11, day: 12))
        #expect(parse("сдать отчёт к 5 дек").due == .day(year: 2026, month: 12, day: 5))
        #expect(parse("сдать отчёт к 5 дек").title == "Сдать отчёт")
        // Already passed this year: the next one.
        #expect(parse("поздравить 3.02").due == .day(year: 2027, month: 2, day: 3))
        #expect(parse("поздравить 1.10.2027").due == .day(year: 2027, month: 10, day: 1))
        #expect(parse("встреча 12 ноября в 12").due == .time(cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!))
        #expect(parse("встреча 12 ноября в 12").title == "Встреча")
    }

    @Test func relative() {
        #expect(parse("проверить деплой через 30 мин").due == .time(at(12.5)))
        #expect(parse("проверить деплой через 2 часа").due == .time(at(14)))
        #expect(parse("проверить деплой через час").due == .time(at(13)))
        #expect(parse("вернуть книгу через 3 дня").due == day(3))
        #expect(parse("проверить деплой через 2 часа").title == "Проверить деплой")
    }

    @Test func estimates() {
        #expect(parse("разобрать почту ~20м").estimate == .m30)
        #expect(parse("переезд на новый сервер ~3ч").estimate == .overHour)
        #expect(parse("созвон ~1 ч").estimate == .h1)
        let apples = parse("купить ~3 яблока")
        #expect(apples.estimate == nil)
        #expect(apples.title == "Купить ~3 яблока")
    }

    @Test func priorityAndTags() {
        #expect(parse("срочно ! позвонить").priority == .low)
        #expect(parse("позвонить !!!").priority == .high)
        // "!" stuck to a word is punctuation.
        let shout = parse("привет!!")
        #expect(shout.priority == .none)
        #expect(shout.title == "Привет!!")
        #expect(parse("релиз #работа #Релиз #работа").tags == ["работа", "Релиз"])
    }

    @Test func onlyMarks() {
        #expect(parse("#работа !!").title.isEmpty)
        #expect(QuickTaskDraft(text: "#работа !!").resolved(filter: TaskFilter(), now: at(12), calendar: cal) == nil)
    }

    @Test func wordsAreWhole() {
        // "сегодняшний" is not "сегодня", "впт" is not "в пт".
        #expect(parse("сегодняшний отчёт").due == nil)
        #expect(parse("кнопка впт").due == nil)
        #expect(parse("кнопка впт").title == "Кнопка впт")
    }

    // MARK: 3.2 Chips and the filter's defaults

    @Test func chips() {
        var draft = QuickTaskDraft()
        draft.setText("купить корм")
        draft.setDue(day(1))
        draft.setList("home")
        let task = draft.resolved(filter: TaskFilter(period: .all), now: at(12), calendar: cal)
        #expect(task == QuickTask(title: "Купить корм", due: day(1), listId: "home"))
    }

    @Test func todayFilterDefaultsToToday() {
        let draft = QuickTaskDraft(text: "прочитать статью")
        #expect(draft.resolved(filter: TaskFilter(period: .today), now: at(12), calendar: cal)?.due == day(0))
        #expect(draft.resolved(filter: TaskFilter(period: .all), now: at(12), calendar: cal)?.due == nil)
        // «Без срока» picked on purpose beats the filter.
        var undated = draft
        undated.setDue(nil)
        #expect(undated.resolved(filter: TaskFilter(period: .today), now: at(12), calendar: cal)?.due == nil)
    }

    @Test func filterListAndTag() {
        var draft = QuickTaskDraft(text: "релизные заметки #срочно")
        let filter = TaskFilter(period: .all, listId: "work", tag: "релиз")
        #expect(draft.resolved(filter: filter, now: at(12), calendar: cal) ==
                QuickTask(title: "Релизные заметки", tags: ["срочно", "релиз"], listId: "work"))
        draft.removeTag("релиз")
        draft.removeTag("срочно")
        #expect(draft.text == "релизные заметки")
        #expect(draft.resolved(filter: filter, now: at(12), calendar: cal)?.tags == [])
    }

    @Test func chipOverTypedText() {
        var draft = QuickTaskDraft()
        draft.setText("отчёт в пт !!")
        draft.setDue(day(1))               // the chip cuts «в пт» out
        #expect(draft.text == "отчёт !!")
        #expect(draft.preview(filter: TaskFilter(), now: at(12), calendar: cal).due == day(1))
        draft.setText("отчёт !! в чт")     // typed again: the text wins
        #expect(draft.preview(filter: TaskFilter(), now: at(12), calendar: cal).due == day(2))
        draft.setPriority(.high)
        #expect(draft.text == "отчёт в чт")
        #expect(draft.preview(filter: TaskFilter(), now: at(12), calendar: cal).priority == .high)
        draft.setEstimate(.m15)
        draft.addTag("#работа")
        let task = draft.resolved(filter: TaskFilter(), now: at(12), calendar: cal)
        #expect(task == QuickTask(title: "Отчёт", due: day(2), priority: .high, tags: ["работа"], estimate: .m15))
        draft.reset()
        #expect(draft == QuickTaskDraft())
    }
}
