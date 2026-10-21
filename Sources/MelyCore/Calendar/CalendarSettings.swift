import Foundation
import Observation

/// Which calendars, how early to remind, and where a meeting opens.
@MainActor
@Observable
public final class CalendarSettings {
    /// Calendars switched off; new calendars show by default.
    public var hiddenCalendars: Set<String> { didSet { save() } }
    /// Minutes before a meeting to remind; 0 turns reminders off.
    public var reminderMinutes: Int { didSet { save() } }
    /// Services whose meetings open in the browser rather than their app.
    public var browserServices: Set<MeetingLink.Service> { didSet { save() } }

    public static let reminderChoices = [0, 1, 2, 5, 10, 15]

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "calendar"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: Self.key)
        hiddenCalendars = Set(saved?["hidden"] as? [String] ?? [])
        reminderMinutes = saved?["reminder"] as? Int ?? 5
        browserServices = Set((saved?["browser"] as? [String] ?? []).compactMap(MeetingLink.Service.init(rawValue:)))
    }

    public func opensInApp(_ service: MeetingLink.Service) -> Bool { !browserServices.contains(service) }

    private func save() {
        defaults.set(["hidden": hiddenCalendars.sorted(), "reminder": reminderMinutes,
                      "browser": browserServices.map(\.rawValue).sorted()], forKey: Self.key)
    }
}

/// Reminders already shown, so each meeting is announced once.
public struct ReminderSchedule: Sendable {
    private var shown: Set<String> = []

    public init() {}

    /// Events whose reminder time has come: starting within `minutes`, not started more
    /// than a minute ago, not announced yet.
    public mutating func due(_ events: [CalendarEvent], minutes: Int, now: Date) -> [CalendarEvent] {
        guard minutes > 0 else { return [] }
        let lead = TimeInterval(minutes * 60)
        let due = events.filter { e in
            !e.isAllDay && !shown.contains(e.id)
                && e.start.timeIntervalSince(now) <= lead && now.timeIntervalSince(e.start) < 60
        }
        shown.formUnion(due.map(\.id))
        return due
    }
}
