import Testing
import Foundation
@testable import MelyCore

@MainActor
@Suite struct FocusStatsTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return c
    }()
    /// Tuesday 2026-10-27, `h` hours in; `d` days later.
    func at(_ h: Double, plusDays d: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: 27 + d))!.addingTimeInterval(h * 3600)
    }
    func record(_ minutes: Double, at start: Date, task: String? = nil) -> FocusRecord {
        FocusRecord(id: UUID().uuidString, taskId: task, taskTitle: task, start: start, worked: minutes * 60)
    }
    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mely-focus-\(UUID().uuidString)")
            .appendingPathComponent("focus-log.json")
    }

    @Test func dayTotal() {
        let records = [record(25, at: at(9)), record(40, at: at(10)), record(40, at: at(11)), record(25, at: at(14))]
        let day = FocusStats.today(records: records, now: at(18), calendar: cal)
        #expect(day == FocusDay(worked: 130 * 60, sessions: 4))
        #expect(day.label == "Фокус сегодня · 2 ч 10 мин · 4 сессии")
    }

    @Test func resetsAtMidnight() {
        let records = [record(25, at: at(23.5)), record(40, at: at(10, plusDays: 1))]
        #expect(FocusStats.today(records: records, now: at(23.9), calendar: cal).sessions == 1)
        let tomorrow = FocusStats.today(records: records, now: at(0.01, plusDays: 1), calendar: cal)
        #expect(tomorrow.sessions == 1)
        #expect(tomorrow.worked == 40 * 60)
        #expect(FocusStats.today(records: [], now: at(12), calendar: cal).label == "Фокус сегодня · 0 мин · 0 сессий")
    }

    @Test func sessionsWord() {
        #expect([1, 2, 5, 11, 21, 22, 112].map(FocusStats.sessionsWord) ==
                ["сессия", "сессии", "сессий", "сессий", "сессия", "сессии", "сессий"])
    }

    @Test func spentPastTheEstimate() {
        let records = [record(40, at: at(10), task: "r1"), record(30, at: at(15), task: "r1"), record(25, at: at(16))]
        let spent = FocusStats.spent(taskId: "r1", records: records)
        #expect(spent == 70 * 60)
        #expect(FocusStats.spentLabel(spent) == "ушло 1 ч 10 мин")
        #expect(FocusStats.exceeds(.m45, spent: spent))
        #expect(!FocusStats.exceeds(.h1 , spent: 60 * 60))
        #expect(!FocusStats.exceeds(.overHour, spent: 5 * 3600))   // «1 ч+» is never passed
        #expect(!FocusStats.exceeds(nil, spent: spent))
        #expect(FocusStats.spentByTask(records: records) == ["r1": 70 * 60])
    }

    @Test func deletedTaskStillCounts() {
        // The task is gone from Reminders: its records stay and count in the day.
        let records = [record(40, at: at(10), task: "gone"), record(25, at: at(11))]
        #expect(FocusStats.today(records: records, now: at(12), calendar: cal).worked == 65 * 60)
    }

    @Test func logAppendsSkipsShortAndRewritesById() throws {
        let url = tempFile()
        let log = FocusLog(fileURL: url, now: at(12))
        log.add(record(0.5, at: at(9)))                    // under a minute: not kept
        #expect(log.records.isEmpty)
        let first = record(40, at: at(10), task: "r1")
        log.add(first)
        log.add(FocusRecord(id: first.id, taskId: "r1", taskTitle: "r1", start: first.start, worked: 50 * 60))
        log.add(record(25, at: at(11)))
        #expect(log.records.map(\.worked) == [TimeInterval(3000), 1500])

        let reopened = FocusLog(fileURL: url, now: at(12))
        #expect(reopened.records == log.records)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }

    @Test func logDropsOldRecords() {
        let url = tempFile()
        let log = FocusLog(fileURL: url, now: at(12))
        log.add(record(30, at: at(10, plusDays: -401)))
        log.add(record(30, at: at(10, plusDays: -399)))
        #expect(log.records.count == 2)
        #expect(FocusLog(fileURL: url, now: at(12)).records.count == 1)
        #expect(FocusLog(fileURL: url, now: at(12)).records.count == 1)   // the file was rewritten
    }

    @Test func settingsDefaultsAndChoices() {
        let defaults = UserDefaults(suiteName: "mely-focus-\(UUID().uuidString)")!
        let settings = FocusSettings(defaults: defaults)
        #expect(settings.defaultMinutes == 25)
        #expect(settings.rhythm == FocusRhythm(shortBreak: 300, longBreak: 900, longEvery: 4))
        #expect(!settings.autoStartsBreak && !settings.autoStartsNext)
        #expect(settings.holdsMessages && settings.warnsMeetings && settings.pausesWhenAway)
        #expect(settings.awayAfter == 300)
        #expect(settings.playsStartSound && settings.playsEndSound)
        #expect(settings.hotKeyCode == 35 && settings.hotKeyModifiers == 0x1800)
        #expect(settings.pickerChoices == [25, 30, 40, 50])

        settings.lastPickedMinutes = 40
        settings.defaultMinutes = 50
        settings.shortBreakMinutes = 10
        let reread = FocusSettings(defaults: defaults)
        #expect(reread.pickerChoices == [40, 25, 30, 50])
        #expect(reread.defaultMinutes == 50)
        #expect(reread.rhythm.shortBreak == 600)
        reread.lastPickedMinutes = 7
        #expect(reread.pickerChoices == [7, 25, 30, 40, 50])
    }
}
