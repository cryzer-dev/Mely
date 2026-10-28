import SwiftUI
import MelyCore

/// Today's tasks for the "Сегодня" tab: what to show and what a click does.
public struct TodayTasks {
    public var items: [TaskItem]
    public let toggle: (String, Bool) -> Void
    /// Opens the "Задачи" tab under «Сегодня», with this task open (nil: just the tab).
    public let open: (String?) -> Void

    public init(items: [TaskItem], toggle: @escaping (String, Bool) -> Void, open: @escaping (String?) -> Void) {
        self.items = items
        self.toggle = toggle
        self.open = open
    }

    /// Today's tasks with a time, done ones too (they stay in the day, dimmed like a past event).
    func timedToday(now: Date, calendar: Calendar = .current) -> [TaskItem] {
        let today = calendar.startOfDay(for: now)
        return items.filter { item in
            guard case .time? = item.due, item.due?.dayStart(calendar: calendar) == today else { return false }
            if let done = item.completedAt { return done >= today }
            return true
        }
    }

    func without(_ ids: Set<String>) -> TodayTasks {
        var copy = self
        copy.items = items.filter { !ids.contains($0.id) }
        return copy
    }

    /// Nothing open overdue or due today.
    func isEmpty(now: Date) -> Bool {
        TaskBoard.todaySummary(items: items, now: now).items.isEmpty
    }
}

/// «Задачи · ~2 ч»: up to five compact rows, «ещё N».
struct TodayTasksBlock: View {
    let tasks: TodayTasks
    let now: Date
    /// No calendar above it: an empty day says so instead of vanishing.
    let alone: Bool
    /// Just marked done: crossed out in place for a moment, as on the "Задачи" tab.
    @State private var lingering: Set<String> = []

    var body: some View {
        let summary = TaskBoard.todaySummary(items: tasks.items, now: now, lingering: lingering)
        if !summary.items.isEmpty || alone {
            VStack(alignment: .leading, spacing: 4) {
                Button { tasks.open(nil) } label: {
                    HStack(spacing: MelySpace.s) {
                        Text("Задачи").font(.system(size: MelyType.caption, weight: .semibold))
                            .foregroundStyle(.white.opacity(MelyInk.secondary))
                        if let load = summary.load {
                            Text(load.text).font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: MelyType.micro, weight: .bold))
                            .foregroundStyle(.white.opacity(MelyInk.tertiary))
                    }
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Открыть вкладку «Задачи»")
                if summary.items.isEmpty {
                    Text("На сегодня задач нет").font(.system(size: MelyType.footnote))
                        .foregroundStyle(.white.opacity(MelyInk.tertiary))
                        .padding(.horizontal, 4)
                }
                ForEach(summary.items) { item in
                    row(item)
                        .layoutProbe("agenda.task.\(item.id)", inside: "agenda.tasks")
                }
                if summary.more > 0 {
                    Button("ещё \(summary.more)") { tasks.open(nil) }
                        .buttonStyle(.plain)
                        .font(.system(size: MelyType.caption, weight: .medium))
                        .foregroundStyle(.white.opacity(MelyInk.secondary))
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func row(_ item: TaskItem) -> some View {
        let overdue = !item.isCompleted && item.due?.isOverdue(now: now) == true
        return HStack(spacing: MelySpace.m) {
            Button {
                let done = !item.isCompleted
                tasks.toggle(item.id, done)
                guard done else { return }
                lingering.insert(item.id)
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(MelyMotion.tab) { _ = lingering.remove(item.id) }
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(item.isCompleted ? MelyTint.done : .white.opacity(MelyInk.secondary))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(item.isCompleted ? "Вернуть в невыполненные" : "Выполнено")
            HStack(spacing: 4) {
                if item.priority != .none {
                    Text(item.priority.marks).font(.system(size: MelyType.body, weight: .bold))
                        .foregroundStyle(MelyTint.approval).fixedSize()
                }
                Text(item.title).font(.system(size: MelyType.body, weight: .medium))
                    .strikethrough(item.isCompleted)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 6)
                if let due = item.due.flatMap({ TaskBoard.rowLabel($0, now: now) }) {
                    Text(due).font(.system(size: MelyType.caption))
                        .foregroundStyle(overdue ? MelyTint.error : .white.opacity(MelyInk.secondary))
                        .fixedSize()
                        .layoutProbe("agenda.task.\(item.id).due", inside: "agenda.task.\(item.id)", checksWhole: true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { tasks.open(item.id) }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.white.opacity(MelyFill.card), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
        .opacity(item.isCompleted ? 0.45 : 1)
    }
}

/// A task with a time, in the day between the events: its time where an event has its
/// start, a circle where an event has its bar.
struct TimelineTaskRow: View {
    let item: TaskItem
    let now: Date
    let toggle: (String, Bool) -> Void
    let open: (String?) -> Void

    var body: some View {
        let due = item.due?.date() ?? now
        let late = !item.isCompleted && due < now
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(due.formatted(date: .omitted, time: .shortened)).font(.system(size: MelyType.body, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(late ? MelyTint.error : .white)
                // Always two lines, as an event's start and end: rows of the day are one height.
                Text(item.estimate?.label ?? " ").font(.system(size: MelyType.caption))
                    .foregroundStyle(.white.opacity(MelyInk.tertiary))
                    .lineLimit(1)
            }
            .frame(width: 44, alignment: .leading)
            Button { toggle(item.id, !item.isCompleted) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(item.isCompleted ? MelyTint.done : .white.opacity(MelyInk.secondary))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(item.isCompleted ? "Вернуть в невыполненные" : "Выполнено")
            // Takes the event bar's width: titles of events and tasks start on one line.
            .frame(width: 3)
            HStack(spacing: 4) {
                if item.priority != .none {
                    Text(item.priority.marks).font(.system(size: MelyType.body, weight: .bold))
                        .foregroundStyle(MelyTint.approval).fixedSize()
                }
                Text(item.title).font(.system(size: MelyType.body, weight: .semibold))
                    .strikethrough(item.isCompleted)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 6)
                Text("задача").font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary)).fixedSize()
            }
            .contentShape(Rectangle())
            .onTapGesture { open(item.id) }
        }
        .frame(minHeight: AgendaView.rowHeight)
        .padding(.horizontal, 10).padding(.vertical, 6)
        // Lighter than an event: an outline, not a filled card.
        .background(RoundedRectangle(cornerRadius: MelyRadius.medium).strokeBorder(.white.opacity(MelyFill.raised)))
        .opacity(item.isCompleted ? 0.45 : 1)
    }
}
