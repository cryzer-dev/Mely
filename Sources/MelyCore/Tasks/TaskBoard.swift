import Foundation

/// What the "Задачи" tab shows: a period, and optionally one list or one tag.
public struct TaskFilter: Codable, Equatable, Sendable {
    public enum Period: String, Codable, CaseIterable, Sendable {
        /// Overdue and today.
        case today
        /// Overdue, today and the next 7 days, by day.
        case soon
        /// Everything not done, with "Без срока" at the end.
        case all

        public var title: String {
            switch self {
            case .today: "Сегодня"
            case .soon: "Скоро"
            case .all: "Все"
            }
        }
    }

    public var period: Period
    public var listId: String?
    public var tag: String?

    public init(period: Period = .today, listId: String? = nil, tag: String? = nil) {
        self.period = period
        self.listId = listId
        self.tag = tag
    }
}

/// The sum of a group's estimates: "~2 ч 30 мин · +1 без оценки", "от ~1 ч 30 мин".
public struct TaskLoad: Equatable, Sendable {
    public let minutes: Int
    /// A "1 ч+" task is in: the sum is a lower bound.
    public let hasOverHour: Bool
    public let unestimated: Int

    /// Over the tasks not done yet; nil when none of them has an estimate.
    public init?(_ items: [TaskItem]) {
        let open = items.filter { !$0.isCompleted }
        let estimates = open.compactMap(\.estimate)
        guard !estimates.isEmpty else { return nil }
        minutes = estimates.reduce(0) { $0 + $1.minutes }
        hasOverHour = estimates.contains(.overHour)
        unestimated = open.count - estimates.count
    }

    public var text: String {
        let sum = (hasOverHour ? "от ~" : "~") + TaskEstimate.format(totalMinutes: minutes)
        return unestimated > 0 ? "\(sum) · +\(unestimated) без оценки" : sum
    }
}

public struct TaskGroup: Identifiable, Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        case overdue
        /// The start of the day.
        case day(Date)
        case undated
    }

    public let kind: Kind
    public let title: String
    /// Not done first, in order; today's done ones at the end.
    public let items: [TaskItem]
    /// Nil for "Без срока" and when nothing in the group has an estimate.
    public let load: TaskLoad?

    public var id: String {
        switch kind {
        case .overdue: "overdue"
        case let .day(date): "day-\(Int(date.timeIntervalSince1970))"
        case .undated: "undated"
        }
    }
}

/// Tasks laid out for the tab. Pure: the app passes all open tasks and today's done ones.
public struct TaskBoard: Equatable, Sendable {
    public let groups: [TaskGroup]
    /// Open tasks over the limit ("ещё N — открыть в Напоминаниях").
    public let hiddenCount: Int

    public static let limit = 300

    public var isEmpty: Bool { groups.isEmpty }

    public static func make(items: [TaskItem], filter: TaskFilter, now: Date, calendar: Calendar = .current,
                            limit: Int = limit) -> TaskBoard {
        let today = calendar.startOfDay(for: now)
        let soonEnd = calendar.date(byAdding: .day, value: 8, to: today) ?? today
        let tag = filter.tag?.lowercased()
        let shown = items.filter { item in
            if let listId = filter.listId, item.listId != listId { return false }
            if let tag, !item.tags.contains(where: { $0.lowercased() == tag }) { return false }
            // Done ones only while it is still the day they were done.
            if let done = item.completedAt, done < today { return false }
            return true
        }

        var overdue: [TaskItem] = []
        var days: [Date: [TaskItem]] = [:]
        var undated: [TaskItem] = []
        for item in shown {
            guard let due = item.due else {
                if filter.period == .all { undated.append(item) }
                continue
            }
            if due.isOverdue(now: now, calendar: calendar) {
                overdue.append(item)
                continue
            }
            let day = due.dayStart(calendar: calendar)
            switch filter.period {
            case .today where day != today: continue
            case .soon where day >= soonEnd: continue
            default: days[day, default: []].append(item)
            }
        }

        var groups: [TaskGroup] = []
        func add(_ kind: TaskGroup.Kind, _ title: String, _ items: [TaskItem], load: Bool = true) {
            guard !items.isEmpty else { return }
            let sorted = sort(items, calendar: calendar)
            groups.append(TaskGroup(kind: kind, title: title, items: sorted, load: load ? TaskLoad(sorted) : nil))
        }
        add(.overdue, "Просрочено", overdue)
        for day in days.keys.sorted() {
            add(.day(day), title(of: day, today: today, calendar: calendar), days[day] ?? [])
        }
        add(.undated, "Без срока", undated, load: false)
        return capped(groups, limit: limit)
    }

    /// The compact block on the "Сегодня" tab: overdue and today, open first, at most `limit`.
    public static func todaySummary(items: [TaskItem], now: Date, calendar: Calendar = .current,
                                    limit: Int = 5) -> (items: [TaskItem], more: Int, load: TaskLoad?) {
        let board = make(items: items, filter: TaskFilter(period: .today), now: now, calendar: calendar)
        let all = board.groups.flatMap(\.items)
        let ordered = all.filter { !$0.isCompleted } + all.filter(\.isCompleted)
        return (Array(ordered.prefix(limit)), max(0, ordered.count - limit), TaskLoad(all))
    }

    /// Open tasks first: timed by time, then by priority, then by title; done ones after.
    static func sort(_ items: [TaskItem], calendar: Calendar) -> [TaskItem] {
        func key(_ item: TaskItem) -> (Int, Date, Int, String) {
            let due = item.due
            // Within a day, a time comes before "any time that day".
            let date = due.map { $0.hasTime ? $0.date(calendar: calendar) : $0.dayStart(calendar: calendar).addingTimeInterval(86_400) }
            return (item.isCompleted ? 1 : 0, date ?? .distantFuture, -item.priority.rawValue, item.title.lowercased())
        }
        return items.sorted { a, b in
            let ka = key(a), kb = key(b)
            if ka.0 != kb.0 { return ka.0 < kb.0 }
            if ka.1 != kb.1 { return ka.1 < kb.1 }
            if ka.2 != kb.2 { return ka.2 < kb.2 }
            return ka.3 < kb.3
        }
    }

    /// Keeps the first `limit` open tasks, in group order.
    private static func capped(_ groups: [TaskGroup], limit: Int) -> TaskBoard {
        var left = limit
        var hidden = 0
        var kept: [TaskGroup] = []
        for group in groups {
            var items: [TaskItem] = []
            for item in group.items {
                if item.isCompleted { items.append(item); continue }
                if left > 0 { items.append(item); left -= 1 } else { hidden += 1 }
            }
            if !items.isEmpty { kept.append(TaskGroup(kind: group.kind, title: group.title, items: items, load: group.load)) }
        }
        return TaskBoard(groups: kept, hiddenCount: hidden)
    }

    private static let weekdays = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
    private static let months = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]

    /// "Сегодня", "Завтра", "Чт, 30 окт".
    static func title(of day: Date, today: Date, calendar: Calendar) -> String {
        let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        if offset == 0 { return "Сегодня" }
        if offset == 1 { return "Завтра" }
        let c = calendar.dateComponents([.weekday, .day, .month], from: day)
        return "\(weekdays[(c.weekday ?? 1) - 1]), \(c.day ?? 1) \(months[(c.month ?? 1) - 1])"
    }
}
