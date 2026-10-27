import Foundation
import Observation

/// What is counted, and nothing else (openspec usage-telemetry): no free text anywhere, so
/// a title, a message or a path cannot get into a signal.
public enum UsageCounter: Hashable, Sendable {
    case islandOpened
    case tabOpened(Tab)
    /// From a reminder, the "Сегодня" tab or the hotkey alike.
    case meetingJoined

    public enum Tab: String, CaseIterable, Sendable {
        case sessions, chat, today, music, notifications
    }

    /// The key in the saved counts.
    public var key: String {
        switch self {
        case .islandOpened: "islandOpened"
        case .tabOpened(let tab): "tab.\(tab.rawValue)"
        case .meetingJoined: "meetingJoined"
        }
    }

    public static var allKeys: Set<String> {
        Set([islandOpened, meetingJoined].map(\.key) + Tab.allCases.map { tabOpened($0).key })
    }
}

/// One day's counts, ready to send: one signal per counter, the count as its number.
public struct UsageSummary: Equatable, Sendable {
    public struct Signal: Equatable, Sendable {
        public let name: String
        public let parameters: [String: String]
        public let value: Double
    }

    /// "2026-10-27": the day counted, not the day sent.
    public let day: String
    public let counts: [String: Int]

    /// `integrations`: ids of what is on ("calendar,claude-code"), from a fixed list.
    public func signals(integrations: [String]) -> [Signal] {
        let base = ["day": day, "integrations": integrations.sorted().joined(separator: ",")]
        return counts.keys.sorted().compactMap { key in
            guard let count = counts[key], count > 0 else { return nil }
            if key.hasPrefix("tab.") {
                return Signal(name: "Usage.tabOpened", parameters: base.merging(["tab": String(key.dropFirst(4))]) { a, _ in a },
                              value: Double(count))
            }
            return Signal(name: "Usage.\(key)", parameters: base, value: Double(count))
        }
    }
}

/// Counts of the day so far, kept across launches; handed over as a summary once the day
/// changes (the first count, a wake or a launch on a later day). Nothing is sent on quit:
/// the counts wait on disk.
public struct UsageCounters {
    private let defaults: UserDefaults
    private static let key = "usageCounters"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var saved: (day: String, counts: [String: Int])? {
        guard let dict = defaults.dictionary(forKey: Self.key), let day = dict["day"] as? String,
              let counts = dict["counts"] as? [String: Int] else { return nil }
        return (day, counts.filter { UsageCounter.allKeys.contains($0.key) })
    }

    /// Counts one; a summary of the previous day when this is the first count of a new one.
    public func bump(_ counter: UsageCounter, now: Date = Date()) -> UsageSummary? {
        let today = Self.day(now)
        let previous = rollover(now: now)
        var counts = saved?.day == today ? saved?.counts ?? [:] : [:]
        counts[counter.key, default: 0] += 1
        defaults.set(["day": today, "counts": counts], forKey: Self.key)
        return previous
    }

    /// The previous day's summary once the day has changed (a launch or a wake in the morning).
    public func rollover(now: Date = Date()) -> UsageSummary? {
        guard let saved, saved.day != Self.day(now) else { return nil }
        reset()
        return saved.counts.isEmpty ? nil : UsageSummary(day: saved.day, counts: saved.counts)
    }

    public func reset() {
        defaults.removeObject(forKey: Self.key)
    }

    static func day(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Settings → Основные → Статистика.
@MainActor
@Observable
public final class TelemetrySettings {
    /// On by default; off sends nothing and forgets what was counted.
    public var isOn: Bool { didSet { save(); changed?() } }
    /// «Помогите улучшить Mely» was shown once.
    public var announced: Bool { didSet { save() } }
    @ObservationIgnored public var changed: (() -> Void)?
    /// Bumped to bring the switch into view in the settings; not saved.
    public var reveal = 0

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "telemetry"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: Self.key)
        isOn = saved?["on"] as? Bool ?? true
        announced = saved?["announced"] as? Bool ?? false
    }

    private func save() {
        defaults.set(["on": isOn, "announced": announced], forKey: Self.key)
    }
}
