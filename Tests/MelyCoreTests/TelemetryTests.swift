import Testing
import Foundation
@testable import MelyCore

@Suite struct TelemetryTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "mely-telemetry-\(UUID().uuidString)"))
    }

    let monday = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 18))!
    var tuesday: Date { monday.addingTimeInterval(16 * 3600) }

    @Test func countsTheDayAndHandsItOverOnTheNext() throws {
        let d = try defaults()
        let counters = UsageCounters(defaults: d)
        #expect(counters.bump(.islandOpened, now: monday) == nil)
        #expect(counters.bump(.islandOpened, now: monday) == nil)
        #expect(counters.bump(.tabOpened(.today), now: monday) == nil)
        // Counts survive a restart.
        let again = UsageCounters(defaults: d)
        let summary = again.bump(.meetingJoined, now: tuesday)
        #expect(summary == UsageSummary(day: "2026-10-26", counts: ["islandOpened": 2, "tab.today": 1]))
        // Tuesday starts from its own first count.
        #expect(again.rollover(now: tuesday.addingTimeInterval(86400)) == UsageSummary(day: "2026-10-27", counts: ["meetingJoined": 1]))
    }

    @Test func wakeInTheMorningSendsYesterday() throws {
        let counters = UsageCounters(defaults: try defaults())
        _ = counters.bump(.islandOpened, now: monday)
        #expect(counters.rollover(now: monday) == nil)
        #expect(counters.rollover(now: tuesday)?.counts == ["islandOpened": 1])
        #expect(counters.rollover(now: tuesday) == nil)
    }

    @Test func signalsCarryOnlyFixedKeys() {
        let summary = UsageSummary(day: "2026-10-26", counts: ["islandOpened": 30, "tab.today": 5, "tab.chat": 1, "meetingJoined": 2])
        let signals = summary.signals(integrations: ["notifications", "calendar"])
        #expect(signals.map(\.name) == ["Usage.islandOpened", "Usage.meetingJoined", "Usage.tabOpened", "Usage.tabOpened"])
        #expect(signals.map(\.value) == [30, 2, 1, 5])
        #expect(signals[3].parameters == ["day": "2026-10-26", "integrations": "calendar,notifications", "tab": "today"])
        for signal in signals {
            #expect(Set(signal.parameters.keys).isSubset(of: ["day", "integrations", "tab"]))
        }
        #expect(UsageCounter.allKeys == ["islandOpened", "meetingJoined", "tab.sessions", "tab.chat", "tab.today", "tab.tasks",
                                         "tab.music", "tab.notifications"])
    }

    @Test func unknownSavedKeysAreDropped() throws {
        let d = try defaults()
        d.set(["day": "2026-10-26", "counts": ["islandOpened": 1, "secret": 5]], forKey: "usageCounters")
        #expect(UsageCounters(defaults: d).rollover(now: monday.addingTimeInterval(86400))?.counts == ["islandOpened": 1])
    }

    @MainActor @Test func settingsDefaultsAndPersistence() throws {
        let d = try defaults()
        let settings = TelemetrySettings(defaults: d)
        #expect(settings.isOn && !settings.announced)
        var told = 0
        settings.changed = { told += 1 }
        settings.isOn = false
        settings.announced = true
        #expect(told == 1)
        let again = TelemetrySettings(defaults: d)
        #expect(!again.isOn && again.announced)
    }
}
