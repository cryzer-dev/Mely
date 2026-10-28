import Foundation

/// A task from Apple Reminders, flattened for the "Задачи" tab.
public struct TaskItem: Identifiable, Equatable, Sendable {
    /// EventKit's `calendarItemIdentifier`.
    public let id: String
    public var title: String
    public var due: TaskDue?
    public var priority: TaskPriority
    /// Tags and the estimate, kept in the last line of the task's notes.
    public var marks: TaskMarks
    public var listId: String
    public var listTitle: String
    /// Set once done; only today's done tasks are shown.
    public var completedAt: Date?
    public var url: URL?

    public init(id: String, title: String, due: TaskDue? = nil, priority: TaskPriority = .none, marks: TaskMarks = TaskMarks(),
                listId: String = "", listTitle: String = "", completedAt: Date? = nil, url: URL? = nil) {
        self.id = id
        self.title = title
        self.due = due
        self.priority = priority
        self.marks = marks
        self.listId = listId
        self.listTitle = listTitle
        self.completedAt = completedAt
        self.url = url
    }

    public var isCompleted: Bool { completedAt != nil }
    public var tags: [String] { marks.tags }
    public var estimate: TaskEstimate? { marks.estimate }
}

/// A Reminders list.
public struct TaskList: Identifiable, Equatable, Sendable {
    /// EventKit's `calendarIdentifier`.
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// When a task is due: a day, or a moment on that day.
public enum TaskDue: Hashable, Sendable {
    case day(year: Int, month: Int, day: Int)
    case time(Date)

    /// From EventKit's `dueDateComponents`: an hour makes it a time.
    public init?(components: DateComponents, calendar: Calendar = .current) {
        if components.hour != nil {
            guard let date = calendar.date(from: components) else { return nil }
            self = .time(date)
        } else {
            guard let year = components.year, let month = components.month, let day = components.day else { return nil }
            self = .day(year: year, month: month, day: day)
        }
    }

    /// The day of a date, without time.
    public static func day(of date: Date, calendar: Calendar = .current) -> TaskDue {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return .day(year: c.year ?? 0, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// For EventKit's `dueDateComponents`.
    public func components(calendar: Calendar = .current) -> DateComponents {
        switch self {
        case let .day(year, month, day):
            DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day)
        case let .time(date):
            calendar.dateComponents(in: calendar.timeZone, from: date).keeping([.year, .month, .day, .hour, .minute])
        }
    }

    public var hasTime: Bool { if case .time = self { true } else { false } }

    /// The start of the due day.
    public func dayStart(calendar: Calendar = .current) -> Date {
        switch self {
        case let .day(year, month, day):
            calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
        case let .time(date):
            calendar.startOfDay(for: date)
        }
    }

    /// The moment it is due: the time, or the start of the day.
    public func date(calendar: Calendar = .current) -> Date {
        if case let .time(date) = self { return date }
        return dayStart(calendar: calendar)
    }

    /// The same due on another day: «На завтра» keeps 15:00 at 15:00.
    public func moved(toDayOf date: Date, calendar: Calendar = .current) -> TaskDue {
        guard case let .time(old) = self else { return .day(of: date, calendar: calendar) }
        let t = calendar.dateComponents([.hour, .minute], from: old)
        let day = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day).map(TaskDue.time)
            ?? .day(of: date, calendar: calendar)
    }

    /// A day is overdue from the next day on; a time, from that moment.
    public func isOverdue(now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .day: dayStart(calendar: calendar) < calendar.startOfDay(for: now)
        case let .time(date): date < now
        }
    }
}

private extension DateComponents {
    func keeping(_ units: Set<Calendar.Component>) -> DateComponents {
        var c = DateComponents(calendar: calendar, timeZone: timeZone)
        for unit in units { c.setValue(value(for: unit), for: unit) }
        return c
    }
}

/// Reminders' priority. EventKit stores 0–9: 1–4 high, 5 medium, 6–9 low; the Reminders
/// app writes 1, 5 and 9.
public enum TaskPriority: Int, Comparable, CaseIterable, Sendable {
    case none = 0, low, medium, high

    public init(eventKit value: Int) {
        switch value {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    public var eventKitValue: Int {
        switch self {
        case .none: 0
        case .low: 9
        case .medium: 5
        case .high: 1
        }
    }

    /// "!", "!!", "!!!"; empty for none.
    public var marks: String { String(repeating: "!", count: rawValue) }

    public static func < (a: TaskPriority, b: TaskPriority) -> Bool { a.rawValue < b.rawValue }
}
