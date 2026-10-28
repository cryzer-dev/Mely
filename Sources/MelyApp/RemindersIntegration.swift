import AppKit
import EventKit
import Observation
import OSLog
import MelyCore
import MelyUI

private let log = Logger(subsystem: "dev.mely.app", category: "reminders")

/// Tasks from Apple Reminders (EventKit): the "Задачи" tab, today's tasks under the
/// agenda, due reminders under the notch, «В задачи» from a session.
@MainActor
@Observable
final class RemindersIntegration: Integration {
    let id = "reminders"
    let displayName = "Задачи"
    let summary = "Задачи из Напоминаний: на сегодня, быстрое добавление, перенос и отметка"
    let requiredPermissions: [SystemPermission] = [.reminders]
    private(set) var status: IntegrationStatus = .off
    /// Open tasks and today's done ones from the lists shown; empty while off.
    private(set) var items: [TaskItem] = []
    /// Every Reminders list, shown or not (Settings, «Список» chips).
    private(set) var lists: [TaskList] = []
    /// False until the first load: "loading", not "no tasks".
    private(set) var hasLoaded = false
    /// A task was just marked done: Mely is glad for a moment.
    private(set) var celebrating = false
    @ObservationIgnored private var celebration: Task<Void, Never>?

    @ObservationIgnored let settings = TaskSettings()
    /// Its own store: switched off, the integration holds nothing (the calendar has its own).
    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Bumped on every load: a slower, older load never overwrites a newer one.
    @ObservationIgnored private var generation = 0
    /// Deleted in the notch, removed from Reminders 4 s later unless «Отменить».
    @ObservationIgnored private var pendingDeletes: [String: Task<Void, Never>] = [:]
    /// Short notices under the notch ("Задача не найдена").
    @ObservationIgnored var peek: ((PeekContent) -> Void)?

    func start() async {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            status = .needsPermission(.reminders)
            // Granted later in System Settings: try again on the next tick.
            scheduleTimer()
            return
        }
        let store = self.store ?? EKEventStore()
        self.store = store
        status = .running
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleReload() }
            }
        }
        reload()
        scheduleTimer()
    }

    func stop() async {
        flushDeletes()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        timer?.invalidate(); timer = nil
        reloadTask?.cancel()
        loadTask?.cancel()
        store = nil
        items = []
        lists = []
        hasLoaded = false
        status = .off
    }

    /// Every 30 s: the day rolls over, due times come, access may have been granted.
    private func scheduleTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.status == .needsPermission(.reminders) {
                    if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess { Task { await self.start() } }
                    return
                }
                self.reload()
            }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Changes come in bursts while iCloud syncs: read once they settle.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    // MARK: - Reading

    /// All open tasks plus today's done ones, from the lists shown.
    func reload() {
        guard let store, status == .running else { return }
        lists = store.calendars(for: .reminder).map { TaskList(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let shown = lists.map(\.id).filter { !settings.hiddenLists.contains($0) }
        generation += 1
        let current = generation
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let loaded = await Self.fetch(store, lists: shown, now: Date())
            guard let self, !Task.isCancelled, current == self.generation else { return }
            self.items = loaded.filter { self.pendingDeletes[$0.id] == nil }
            self.hasLoaded = true
            log.info("loaded \(loaded.count) tasks from \(shown.count) lists")
        }
    }

    /// The store stays on the main actor; EventKit answers on its own queue.
    private static func fetch(_ store: EKEventStore, lists ids: [String], now: Date) async -> [TaskItem] {
        let calendars = store.calendars(for: .reminder).filter { ids.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? now
        let open = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        let done = store.predicateForCompletedReminders(withCompletionDateStarting: today, ending: tomorrow, calendars: calendars)
        let openItems = await fetch(store, open)
        return await openItems + fetch(store, done)
    }

    private static func fetch(_ store: EKEventStore, _ predicate: NSPredicate) async -> [TaskItem] {
        await withCheckedContinuation { done in
            store.fetchReminders(matching: predicate) { reminders in
                done.resume(returning: (reminders ?? []).map(item))
            }
        }
    }

    nonisolated static func item(_ r: EKReminder) -> TaskItem {
        TaskItem(id: r.calendarItemIdentifier,
                 title: r.title?.isEmpty == false ? r.title! : "Без названия",
                 due: r.dueDateComponents.flatMap { TaskDue(components: $0) },
                 priority: TaskPriority(eventKit: r.priority),
                 marks: TaskMarks.parse(notes: r.notes).marks,
                 listId: r.calendar?.calendarIdentifier ?? "",
                 listTitle: r.calendar?.title ?? "",
                 completedAt: r.isCompleted ? (r.completionDate ?? Date()) : nil,
                 url: r.url)
    }

    // MARK: - Writing

    /// A new task in its list, or the list for new tasks; a due time gets an alarm.
    @discardableResult
    func create(_ task: QuickTask) -> TaskItem? {
        guard let store else { return nil }
        let r = EKReminder(eventStore: store)
        r.title = task.title
        r.calendar = list(for: task.listId, in: store)
        r.priority = task.priority.eventKitValue
        r.notes = TaskMarks.write(TaskMarks(tags: task.tags, estimate: task.estimate), into: nil)
        if let due = task.due { apply(due, to: r) }
        guard save(r) else { return nil }
        let item = Self.item(r)
        items.append(item)
        log.info("created a task")
        return item
    }

    func setCompleted(_ id: String, _ done: Bool) {
        change(id) { $0.isCompleted = done }
        if done { celebrate() }
    }

    private func celebrate() {
        celebrating = true
        celebration?.cancel()
        celebration = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.celebrating = false
        }
    }

    func rename(_ id: String, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        change(id) { $0.title = title }
    }

    func setPriority(_ id: String, _ priority: TaskPriority) {
        change(id) { $0.priority = priority.eventKitValue }
    }

    /// Tags and the estimate: the last line of the notes, the rest left as it is.
    func setMarks(_ id: String, _ marks: TaskMarks) {
        change(id) { $0.notes = TaskMarks.write(marks, into: $0.notes) }
    }

    func move(_ id: String, toList listId: String) {
        guard let store, let list = store.calendar(withIdentifier: listId) else { return }
        change(id) { $0.calendar = list }
    }

    /// A new due (nil: «Без срока»); alarms follow it.
    func setDue(_ id: String, _ due: TaskDue?) {
        change(id) { r in
            if let due { self.apply(due, to: r) } else {
                r.dueDateComponents = nil
                for alarm in r.alarms ?? [] where alarm.absoluteDate != nil { r.removeAlarm(alarm) }
            }
        }
    }

    /// «На завтра», «На понедельник»: another day, the same time.
    func move(_ id: String, toDayOf date: Date) {
        guard let due = items.first(where: { $0.id == id })?.due else {
            setDue(id, .day(of: date))
            return
        }
        setDue(id, due.moved(toDayOf: date))
    }

    /// «+1 ч» on a due reminder: an hour from now.
    func postponeHour(_ id: String) {
        let date = Date().addingTimeInterval(3600)
        setDue(id, .time(Calendar.current.date(bySetting: .second, value: 0, of: date) ?? date))
    }

    /// «Всё на сегодня»: overdue tasks to today, keeping their times.
    func moveOverdueToToday(_ ids: [String]) {
        let now = Date()
        for id in ids { move(id, toDayOf: now) }
    }

    /// Opens the task in Reminders; the app itself if the link does not work.
    func open(_ id: String) {
        let workspace = NSWorkspace.shared
        if let external = reminder(id)?.calendarItemExternalIdentifier,
           let url = URL(string: "x-apple-reminderkit://REMCDReminder/\(external)"), workspace.open(url) { return }
        if let app = workspace.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            workspace.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: Deleting

    /// Gone from the notch at once, from Reminders in 4 s unless `undoDelete`.
    func delete(_ id: String) {
        items.removeAll { $0.id == id }
        pendingDeletes[id]?.cancel()
        pendingDeletes[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.commitDelete(id)
        }
    }

    /// «Отменить»: nothing was removed, the task comes back as it was.
    func undoDelete(_ id: String) {
        guard let pending = pendingDeletes.removeValue(forKey: id) else { return }
        pending.cancel()
        reload()
    }

    /// On quit and switch-off: deletes still waiting happen now.
    func flushDeletes() {
        for id in Array(pendingDeletes.keys) {
            pendingDeletes.removeValue(forKey: id)?.cancel()
            commitDelete(id)
        }
    }

    private func commitDelete(_ id: String) {
        pendingDeletes.removeValue(forKey: id)
        guard let store, let r = reminder(id) else { return }
        do {
            try store.remove(r, commit: true)
            log.info("deleted a task")
        } catch {
            log.error("delete failed: \(error.localizedDescription, privacy: .public)")
            failed("Не удалось удалить задачу")
        }
    }

    // MARK: Helpers

    private func reminder(_ id: String) -> EKReminder? {
        store?.calendarItem(withIdentifier: id) as? EKReminder
    }

    /// Finds the task, changes it, saves, and updates the model at once (the store's
    /// change notification comes later).
    private func change(_ id: String, _ edit: (EKReminder) -> Void) {
        guard let r = reminder(id) else {
            peek?(PeekContent(id: "task-missing", symbol: "questionmark.circle", tint: .gray,
                              title: "Задача не найдена", subtitle: "Её изменили или удалили в Напоминаниях"))
            reload()
            return
        }
        edit(r)
        guard save(r) else { return }
        let updated = Self.item(r)
        if let i = items.firstIndex(where: { $0.id == id }) { items[i] = updated }
    }

    private func save(_ r: EKReminder) -> Bool {
        guard let store else { return false }
        do {
            try store.save(r, commit: true)
            return true
        } catch {
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
            store.reset()
            failed("Не удалось сохранить задачу")
            reload()
            return false
        }
    }

    private func failed(_ title: String) {
        peek?(PeekContent(id: "task-failed", symbol: "exclamationmark.triangle.fill", tint: .orange,
                          title: title, subtitle: "Попробуйте ещё раз в Напоминаниях"))
    }

    /// Sets the due. A time gets one alarm at that time (replacing the old absolute ones);
    /// a day keeps its alarms, moved by as many days as the due.
    private func apply(_ due: TaskDue, to r: EKReminder) {
        let cal = Calendar.current
        let oldDay = r.dueDateComponents.flatMap { TaskDue(components: $0) }?.dayStart()
        r.dueDateComponents = due.components()
        let absolute = (r.alarms ?? []).filter { $0.absoluteDate != nil }
        switch due {
        case let .time(date):
            absolute.forEach(r.removeAlarm)
            r.addAlarm(EKAlarm(absoluteDate: date))
        case .day:
            guard let oldDay else { return }
            let days = cal.dateComponents([.day], from: oldDay, to: due.dayStart()).day ?? 0
            guard days != 0 else { return }
            for alarm in absolute {
                guard let date = alarm.absoluteDate, let moved = cal.date(byAdding: .day, value: days, to: date) else { continue }
                r.removeAlarm(alarm)
                r.addAlarm(EKAlarm(absoluteDate: moved))
            }
        }
    }

    /// The task's list when it exists, else the list for new tasks, else Reminders' default.
    private func list(for id: String?, in store: EKEventStore) -> EKCalendar? {
        if let id, let list = store.calendar(withIdentifier: id) { return list }
        let fallback = store.defaultCalendarForNewReminders()
        let chosen = settings.listForNewTasks(available: lists.map(\.id), defaultList: fallback?.calendarIdentifier)
        return chosen.flatMap(store.calendar(withIdentifier:)) ?? fallback
    }
}
