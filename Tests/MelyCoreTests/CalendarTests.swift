import Testing
import Foundation
@testable import MelyCore

@Suite struct CalendarTests {
    let day = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 0))!
    func at(_ h: Double, plusDays d: Double = 0) -> Date { day.addingTimeInterval((d * 24 + h) * 3600) }
    func ev(_ id: String, _ title: String, _ from: Double, _ to: Double, allDay: Bool = false, day d: Double = 0,
            meeting: MeetingLink? = nil) -> CalendarEvent {
        CalendarEvent(id: id, title: title, start: at(from, plusDays: d), end: at(to, plusDays: d), isAllDay: allDay, meeting: meeting)
    }

    @Test func agendaGroupsAndPointsAtTomorrow() {
        let agenda = Agenda(today: [ev("b", "Ретро", 15, 16), ev("a", "Стендап", 10, 10.25), ev("c", "Отпуск Ани", 0, 24, allDay: true)],
                            tomorrow: [])
        #expect(agenda.allDay.map(\.title) == ["Отпуск Ани"])
        #expect(agenda.timed.map(\.title) == ["Стендап", "Ретро"])
        #expect(agenda.timed[0].isNow(at(10.1)))
        #expect(agenda.nextTomorrow == nil)
        let empty = Agenda(today: [], tomorrow: [ev("x", "Демо", 14, 15, day: 1), ev("y", "Планирование", 11, 12, day: 1)])
        #expect(empty.isEmpty)
        #expect(empty.nextTomorrow?.title == "Планирование")
    }

    @Test func nextMeetingBeforeTheFocusEnds() {
        let events = [ev("d", "Отпуск", 0, 24, allDay: true), ev("b", "Ретро", 11.5, 12), ev("a", "Груминг", 11, 11.5),
                      ev("x", "Стендап", 10, 10.25)]
        // A session 10:30–11:20: the grooming at 11:00, not the all-day one or the past standup.
        #expect(CalendarEvent.next(in: events, after: at(10.5), before: at(11.33))?.title == "Груминг")
        // Ends before 11:00: nothing to warn of.
        #expect(CalendarEvent.next(in: events, after: at(10.5), before: at(10.9)) == nil)
        #expect(CalendarEvent.next(in: [ev("d", "Отпуск", 0, 24, allDay: true, day: 1)], after: at(10), before: at(30)) == nil)
    }

    @Test func reminderCountsDownThenCountsUp() {
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        #expect(MeetingCountdown.text(until: start, now: start.addingTimeInterval(-300)) == "через 5 мин")
        #expect(MeetingCountdown.text(until: start, now: start.addingTimeInterval(-241)) == "через 5 мин")
        #expect(MeetingCountdown.text(until: start, now: start.addingTimeInterval(-59)) == "через 1 мин")
        #expect(MeetingCountdown.text(until: start, now: start) == "сейчас")
        #expect(MeetingCountdown.text(until: start, now: start.addingTimeInterval(59)) == "сейчас")
        #expect(MeetingCountdown.text(until: start, now: start.addingTimeInterval(60)) == "идёт 1 мин")
        #expect(MeetingCountdown.text(until: start, now: start.addingTimeInterval(40 * 60 + 30)) == "идёт 40 мин")
    }

    @Test func joinableMeeting() throws {
        let link = MeetingLink(service: .telemost, url: URL(string: "https://telemost.yandex.ru/j/123")!)
        let agenda = Agenda(today: [ev("a", "Без ссылки", 10, 11), ev("b", "Синк", 11, 12, meeting: link)], tomorrow: [])
        #expect(agenda.joinable(now: at(10.5)) == nil)                  // 30 minutes away: not yet
        #expect(agenda.joinable(now: at(10.9))?.title == "Синк")        // in 6 minutes
        #expect(agenda.joinable(now: at(11.5))?.title == "Синк")        // running
    }

    @Test func snapshotFindsNewAndMovedButNotTheFirstLook() {
        var snapshot = EventSnapshot()
        #expect(snapshot.update([ev("a", "Стендап", 10, 10.25), ev("b", "Ретро", 15, 16)]).isEmpty)
        let changes = snapshot.update([ev("a", "Стендап", 10, 10.25), ev("b", "Ретро", 16, 17), ev("c", "Интервью", 12, 13)])
        #expect(changes.added.map(\.title) == ["Интервью"])
        #expect(changes.moved.map(\.event.title) == ["Ретро"])
        #expect(changes.moved.first?.oldStart == at(15))
        #expect(snapshot.update([ev("a", "Стендап", 10, 10.25), ev("b", "Ретро", 16, 17), ev("c", "Интервью", 12, 13)]).isEmpty)
    }

    @Test func snapshotFindsCancelledEvents() {
        var snapshot = EventSnapshot()
        let now = at(11)
        let all = [ev("a", "Стендап", 10, 10.25), ev("b", "Груминг", 14, 15), ev("c", "Демо", 12, 13, day: 1)]
        _ = snapshot.update(all, now: now)
        // Groom deleted; the stand-up is over, so its going is no news.
        let changes = snapshot.update([ev("c", "Демо", 12, 13, day: 1)], now: now)
        #expect(changes.removed.map(\.title) == ["Груминг"])
        #expect(changes.removed.first?.start == at(14))
        #expect(changes.added.isEmpty && changes.moved.isEmpty)
        // Once told, not again.
        #expect(snapshot.update([ev("c", "Демо", 12, 13, day: 1)], now: now).isEmpty)
    }

    @Test func emptyLookIsNotACancellation() {
        var snapshot = EventSnapshot()
        let now = at(11)
        _ = snapshot.update([ev("b", "Груминг", 14, 15)], now: now)
        // The calendar did not answer: nothing changed, and nothing is forgotten.
        #expect(snapshot.update([], now: now).isEmpty)
        #expect(snapshot.update([ev("b", "Груминг", 14, 15)], now: now).isEmpty)
    }

    @Test func movedEventIsRemindedAgain() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let meeting = CalendarEvent(id: "m", title: "Синк", start: t0.addingTimeInterval(240), end: t0.addingTimeInterval(2400), isAllDay: false)
        var schedule = ReminderSchedule()
        #expect(schedule.due([meeting], minutes: 5, now: t0).map(\.id) == ["m"])
        let moved = CalendarEvent(id: "m", title: "Синк", start: t0.addingTimeInterval(3600), end: t0.addingTimeInterval(5400), isAllDay: false)
        #expect(schedule.due([moved], minutes: 5, now: t0.addingTimeInterval(3360)).isEmpty)   // already reminded
        schedule.forget("m")
        #expect(schedule.due([moved], minutes: 5, now: t0.addingTimeInterval(3000)).isEmpty)   // not yet: 10 minutes away
        #expect(schedule.due([moved], minutes: 5, now: t0.addingTimeInterval(3360)).map(\.id) == ["m"])
    }

    @Test func findsCallLinks() {
        let inNotes = MeetingLink.find(url: nil, location: "Переговорка 3",
                                       notes: "Повестка…\nСсылка: https://telemost.yandex.ru/j/5512345678 до встречи")
        #expect(inNotes?.service == .telemost)
        #expect(inNotes?.url.absoluteString == "https://telemost.yandex.ru/j/5512345678")
        #expect(MeetingLink.find(url: URL(string: "https://us02web.zoom.us/j/8312?pwd=abc"), location: nil, notes: nil)?.service == .zoom)
        #expect(MeetingLink.find(url: nil, location: "https://meet.google.com/abc-defg-hij", notes: nil)?.service == .meet)
        #expect(MeetingLink.find(url: nil, location: "офис", notes: "без ссылки") == nil)
    }

    @Test func findsUnknownCallLinks() {
        let jitsi = MeetingLink.find(url: nil, location: "https://meet.jit.si/retro-team", notes: nil)
        #expect(jitsi?.service == .other)
        #expect(jitsi?.url.absoluteString == "https://meet.jit.si/retro-team")
        #expect(jitsi?.name == "meet.jit.si")
        #expect(MeetingLink.find(url: nil, location: "Переговорка", notes: "Звонок: https://ktalk.ru/abc")?.url.host == "ktalk.ru")
        // The url field first, then the location, then the notes.
        #expect(MeetingLink.find(url: URL(string: "https://www.webinar.example.ru/room"), location: "https://a.example.com",
                                 notes: nil)?.name == "webinar.example.ru")
        // A known service wins wherever it stands.
        let known = MeetingLink.find(url: nil, location: nil,
                                     notes: "Документ: https://docs.example.com/plan\nhttps://telemost.yandex.ru/j/55")
        #expect(known?.service == .telemost)
        // The event's own page in the calendar is not a call.
        #expect(MeetingLink.find(url: URL(string: "https://calendar.yandex.ru/event?event_id=1"), location: nil, notes: nil) == nil)
        #expect(MeetingLink.find(url: nil, location: "офис", notes: "без ссылки") == nil)
    }

    @Test func appLinks() {
        let zoom = MeetingLink(service: .zoom, url: URL(string: "https://us02web.zoom.us/j/8312345678?pwd=Xy12")!)
        #expect(zoom.appURL?.absoluteString == "zoommtg://zoom.us/join?action=join&confno=8312345678&pwd=Xy12")
        let teams = MeetingLink(service: .teams, url: URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d")!)
        #expect(teams.appURL?.absoluteString == "msteams:/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d")
        #expect(MeetingLink(service: .telemost, url: URL(string: "https://telemost.yandex.ru/j/1")!).appURL == nil)
        #expect(MeetingLink(service: .meet, url: URL(string: "https://meet.google.com/a")!).appURL == nil)
    }
}

@Suite struct ReminderTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func remindsOnceInTheWindow() {
        let meeting = CalendarEvent(id: "m", title: "Синк", start: t0.addingTimeInterval(600), end: t0.addingTimeInterval(2400), isAllDay: false)
        var schedule = ReminderSchedule()
        #expect(schedule.due([meeting], minutes: 5, now: t0).isEmpty)                       // 10 minutes away
        #expect(schedule.due([meeting], minutes: 5, now: t0.addingTimeInterval(301)).map(\.id) == ["m"])
        #expect(schedule.due([meeting], minutes: 5, now: t0.addingTimeInterval(400)).isEmpty) // once
        var off = ReminderSchedule()
        #expect(off.due([meeting], minutes: 0, now: t0.addingTimeInterval(590)).isEmpty)      // reminders off
    }

    @Test func remindsOfARunningEventUntilItsEnd() {
        let meeting = CalendarEvent(id: "m", title: "Синк", start: t0.addingTimeInterval(600), end: t0.addingTimeInterval(2400), isAllDay: false)
        var late = ReminderSchedule()
        #expect(late.due([meeting], minutes: 5, now: t0.addingTimeInterval(1200)).map(\.id) == ["m"]) // Mely started mid-meeting
        #expect(late.due([meeting], minutes: 5, now: t0.addingTimeInterval(1300)).isEmpty)           // once
        var over = ReminderSchedule()
        #expect(over.due([meeting], minutes: 5, now: t0.addingTimeInterval(2400)).isEmpty)          // over
        let allDay = CalendarEvent(id: "d", title: "Дежурство", start: t0, end: t0.addingTimeInterval(86400), isAllDay: true)
        #expect(over.due([allDay], minutes: 5, now: t0.addingTimeInterval(60)).isEmpty)
    }

    @MainActor @Test func settingsPersist() throws {
        let defaults = try #require(UserDefaults(suiteName: "mely-cal-\(UUID().uuidString)"))
        let s = CalendarSettings(defaults: defaults)
        #expect(s.reminderMinutes == 5)
        #expect(s.opensInApp(.telemost))
        s.browserServices.insert(.zoom)
        s.hiddenCalendars.insert("work")
        s.reminderMinutes = 10
        let again = CalendarSettings(defaults: defaults)
        #expect(!again.opensInApp(.zoom))
        #expect(again.hiddenCalendars == ["work"])
        #expect(again.reminderMinutes == 10)
    }
}
