import Foundation
import Observation

/// Which Reminders lists show, where new tasks go, and the tab's last filter.
@MainActor
@Observable
public final class TaskSettings {
    /// Lists switched off; new lists show by default.
    public var hiddenLists: Set<String> { didSet { save() } }
    /// The list for new tasks; nil: Reminders' default list.
    public var newTaskList: String? { didSet { save() } }
    /// Today's tasks under the events on the "Сегодня" tab.
    public var showsInToday: Bool { didSet { save() } }
    /// A due time shows a reminder under the notch.
    public var remindsUnderNotch: Bool { didSet { save() } }
    /// The "Задачи" tab opens where it was left.
    public var filter: TaskFilter { didSet { save() } }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "tasks"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: Self.key)
        hiddenLists = Set(saved?["hidden"] as? [String] ?? [])
        newTaskList = saved?["newList"] as? String
        showsInToday = saved?["today"] as? Bool ?? true
        remindsUnderNotch = saved?["remind"] as? Bool ?? true
        filter = (saved?["filter"] as? Data).flatMap { try? JSONDecoder().decode(TaskFilter.self, from: $0) } ?? TaskFilter()
    }

    /// Where a new task goes: the chosen list while it exists, else Reminders' default.
    public func listForNewTasks(available: [String], defaultList: String?) -> String? {
        if let newTaskList, available.contains(newTaskList) { return newTaskList }
        return defaultList
    }

    private func save() {
        var values: [String: Any] = ["hidden": hiddenLists.sorted(), "today": showsInToday, "remind": remindsUnderNotch]
        if let newTaskList { values["newList"] = newTaskList }
        if let data = try? JSONEncoder().encode(filter) { values["filter"] = data }
        defaults.set(values, forKey: Self.key)
    }
}

/// Due reminders already shown, so each due time is announced once; a new time (after
/// «+1 ч» or a move) is announced again.
public struct TaskReminderSchedule: Sendable {
    private var shown: Set<String> = []

    /// A due time missed while the Mac slept still shows within this.
    public static let catchUp: TimeInterval = 3600

    public init() {}

    /// Open tasks whose due time has come, at most `catchUp` ago, not announced yet.
    public mutating func due(_ items: [TaskItem], now: Date) -> [TaskItem] {
        let due = items.filter { item in
            guard !item.isCompleted, case let .time(date)? = item.due else { return false }
            return date <= now && now.timeIntervalSince(date) < Self.catchUp && !shown.contains(Self.key(item.id, date))
        }
        for item in due { if case let .time(date)? = item.due { shown.insert(Self.key(item.id, date)) } }
        return due
    }

    private static func key(_ id: String, _ date: Date) -> String { "\(id)@\(Int(date.timeIntervalSince1970))" }
}
