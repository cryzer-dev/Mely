import Testing
import Foundation
@testable import MelyCore

@Suite struct CharacterQuirksTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func occasions() {
        // 23.10.2026 is a Friday.
        #expect(CharacterQuirks.occasion(on: date(2026, 10, 23, 18), birthday: nil, calendar: calendar) == .fridayEvening)
        #expect(CharacterQuirks.occasion(on: date(2026, 10, 23, 11), birthday: nil, calendar: calendar) == nil)
        #expect(CharacterQuirks.occasion(on: date(2026, 12, 31), birthday: nil, calendar: calendar) == .newYear)
        #expect(CharacterQuirks.occasion(on: date(2027, 1, 1), birthday: nil, calendar: calendar) == .newYear)
        #expect(CharacterQuirks.occasion(on: date(2026, 5, 14), birthday: MonthDay(5, 14), calendar: calendar) == .birthday)
        #expect(CharacterQuirks.occasion(on: date(2026, 5, 15), birthday: MonthDay(5, 14), calendar: calendar) == nil)
    }

    @Test func rareAndOnlyWhenCalm() {
        #expect(CharacterQuirks.interval.lowerBound >= 180)
        #expect(CharacterQuirks.allowed(in: .idle))
        #expect(!CharacterQuirks.allowed(in: .worried))
        #expect(!CharacterQuirks.allowed(in: .curious))
        #expect(!CharacterQuirks.allowed(in: .scared))
        #expect(!CharacterQuirks.allowed(in: .sleeping))
        #expect(!CharacterQuirks.allowed(in: .working))
        #expect(CharacterQuirks.pick(on: date(2026, 10, 21), birthday: nil, roll: 0.1, calendar: calendar) == .wink)
        #expect(CharacterQuirks.pick(on: date(2026, 12, 31), birthday: nil, roll: 0.1, calendar: calendar) == .party(.newYear))
        #expect(CharacterQuirks.pick(on: date(2026, 12, 31), birthday: nil, roll: 0.9, calendar: calendar) == .wink)
        #expect(CharacterQuirks.birthday(from: "05-14") == MonthDay(5, 14))
        #expect(CharacterQuirks.birthday(from: "13-01") == nil)
    }
}
