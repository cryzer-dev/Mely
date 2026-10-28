import SwiftUI
import MelyCore

/// What the "Задачи" tab does with a task; the app sends it to Reminders.
public struct TasksActions {
    public var setCompleted: (String, Bool) -> Void = { _, _ in }
    public var create: (QuickTask) -> Void = { _ in }
    public var rename: (String, String) -> Void = { _, _ in }
    public var setDue: (String, TaskDue?) -> Void = { _, _ in }
    /// Another day, the same time.
    public var moveToDay: (String, Date) -> Void = { _, _ in }
    public var setPriority: (String, TaskPriority) -> Void = { _, _ in }
    public var setMarks: (String, TaskMarks) -> Void = { _, _ in }
    public var moveToList: (String, String) -> Void = { _, _ in }
    public var moveOverdueToToday: ([String]) -> Void = { _ in }
    public var open: (String) -> Void = { _ in }
    public var delete: (String) -> Void = { _ in }
    public var undoDelete: (String) -> Void = { _ in }

    public init() {}
}

/// The "Задачи" tab: period and list/tag filters on top, the groups, «+ Задача» at the bottom.
public struct TasksView: View {
    let items: [TaskItem]
    let lists: [TaskList]
    let hasLoaded: Bool
    @Bindable var settings: TaskSettings
    @Bindable var tabs: IslandTabs
    let actions: TasksActions
    /// A fixed clock (snapshots); nil: the real one.
    let now: Date?

    @State private var draft = QuickTaskDraft()
    @State private var notice: UndoNotice?
    /// Just marked done: crossed out in place for a moment, then into «Выполнено сегодня».
    @State private var lingering: Set<String> = []
    @State private var showsDone = false

    public init(items: [TaskItem], lists: [TaskList], hasLoaded: Bool = true, settings: TaskSettings, tabs: IslandTabs,
                now: Date? = nil, draft: QuickTaskDraft = QuickTaskDraft(), showsDone: Bool = false,
                deleted: String? = nil, actions: TasksActions) {
        self.items = items
        self.lists = lists
        self.hasLoaded = hasLoaded
        self.settings = settings
        self.tabs = tabs
        self.now = now
        self.actions = actions
        _draft = State(initialValue: draft)
        _showsDone = State(initialValue: showsDone)
        // Snapshots: the line after a delete.
        _notice = State(initialValue: deleted.map { UndoNotice(text: "Удалено: \($0)") {} })
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            page(now: now ?? context.date)
        }
        .foregroundStyle(.white)
    }

    private func page(now: Date) -> some View {
        let board = TaskBoard.make(items: items, filter: settings.filter, now: now, lingering: lingering)
        return VStack(alignment: .leading, spacing: MelySpace.s) {
            TaskFilterBar(filter: $settings.filter, lists: lists, tags: knownTags)
                .layoutProbe("tasks.filters", inside: "content")
            if !hasLoaded {
                placeholder("Читаю задачи…")
            } else if board.isEmpty {
                placeholder("Задач нет")
            } else if board.groups.isEmpty, !showsDone {
                placeholder("Всё сделано")
            } else {
                ScrollViewReader { scroll in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: MelySpace.m) {
                            ForEach(board.groups) { group in
                                groupView(group, now: now)
                            }
                            if board.hiddenCount > 0 {
                                Text("ещё \(board.hiddenCount) — в Напоминаниях")
                                    .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                            }
                            if !board.done.isEmpty { doneSection(board.done, now: now, in: "tasks.list") }
                        }
                    }
                    .onAppear { if let id = tabs.openTask { scroll.scrollTo(id, anchor: .center) } }
                }
                .layoutProbe("tasks.list", inside: "content", scrolls: true)
            }
            if board.groups.isEmpty, !showsDone, !board.done.isEmpty {
                doneSection(board.done, now: now, in: "content")
            }
            if let notice {
                UndoBar(notice: notice) { self.notice = nil }
                    .layoutProbe("tasks.undo", inside: "content")
            }
            QuickTaskLine(draft: $draft, tabs: tabs, filter: settings.filter, lists: lists, tags: knownTags, now: now) { task in
                actions.create(task)
            }
            .layoutProbe("tasks.add", inside: "content")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: notice?.id) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { notice = nil }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.system(size: MelyType.title)).foregroundStyle(.white.opacity(MelyInk.secondary))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutProbe("tasks.empty", inside: "content")
    }

    private var knownTags: [String] {
        TaskMarks(tags: items.flatMap(\.tags)).tags.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    @ViewBuilder
    private func groupView(_ group: TaskGroup, now: Date) -> some View {
        VStack(alignment: .leading, spacing: MelySpace.xs) {
            HStack(spacing: MelySpace.s) {
                Text(group.title).font(.system(size: MelyType.caption, weight: .semibold))
                    .foregroundStyle(group.kind == .overdue ? MelyTint.error : .white.opacity(MelyInk.secondary))
                if let load = group.load {
                    Text(load.text).font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if group.kind == .overdue {
                    Button("Всё на сегодня") {
                        actions.moveOverdueToToday(group.items.filter { !$0.isCompleted }.map(\.id))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: MelyType.caption, weight: .semibold))
                    .foregroundStyle(.white.opacity(MelyInk.strong))
                    .fixedSize()
                    .layoutProbe("tasks.overdue.all", inside: "tasks.group.\(group.id)", checksWhole: true)
                }
            }
            .padding(.horizontal, 4)
            ForEach(group.items) { item in
                Group {
                    if tabs.openTask == item.id {
                        TaskEditor(item: item, lists: lists, tags: knownTags, now: now, tabs: tabs, actions: actions,
                                   close: { tabs.openTask = nil }, delete: { delete(item) })
                            .layoutProbe("tasks.editor", inside: "tasks.list")
                    } else {
                        TaskRow(item: item, now: now, showsList: settings.filter.listId == nil && lists.count > 1,
                                toggle: { toggle(item) }, openEditor: { tabs.openTask = item.id },
                                filterTag: { settings.filter.tag = $0 },
                                menu: { TaskMenu(item: item, now: now, actions: actions,
                                                 pickDate: { tabs.openTask = item.id }, delete: { delete(item) }) })
                            .layoutProbe("tasks.row.\(item.id)", inside: "tasks.list")
                    }
                }
                .id(item.id)
            }
        }
        .layoutProbe("tasks.group.\(group.id)", inside: "tasks.list")
    }

    /// Done: crossed out in place for 2 s (a click on the circle brings it back), then into
    /// «Выполнено сегодня».
    private func toggle(_ item: TaskItem) {
        let done = !item.isCompleted
        actions.setCompleted(item.id, done)
        guard done else { return }
        lingering.insert(item.id)
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(MelyMotion.tab) { _ = lingering.remove(item.id) }
        }
    }

    /// Folded by default: «Выполнено сегодня · 3».
    private func doneSection(_ done: [TaskItem], now: Date, in container: String) -> some View {
        VStack(alignment: .leading, spacing: MelySpace.xs) {
            Button {
                withAnimation(MelyMotion.tab) { showsDone.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right").font(.system(size: MelyType.micro, weight: .bold))
                        .rotationEffect(.degrees(showsDone ? 90 : 0))
                    Text("Выполнено сегодня · \(done.count)").font(.system(size: MelyType.caption, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(MelyInk.tertiary))
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutProbe("tasks.done.header", inside: container)
            if showsDone {
                ForEach(done) { item in
                    TaskRow(item: item, now: now, showsList: settings.filter.listId == nil && lists.count > 1,
                            // Done ones are not edited here: the circle brings one back first.
                            toggle: { toggle(item) }, openEditor: {},
                            filterTag: { settings.filter.tag = $0 },
                            menu: { TaskMenu(item: item, now: now, actions: actions,
                                             pickDate: {}, delete: { delete(item) }) })
                        .layoutProbe("tasks.done.\(item.id)", inside: container)
                }
            }
        }
    }

    private func delete(_ item: TaskItem) {
        if tabs.openTask == item.id { tabs.openTask = nil }
        actions.delete(item.id)
        notice = UndoNotice(text: "Удалено: \(item.title)") { actions.undoDelete(item.id) }
    }
}

/// «Отменить» for 4 seconds after a task is done or deleted.
struct UndoNotice: Identifiable {
    let id = UUID()
    let text: String
    let undo: () -> Void
}

private struct UndoBar: View {
    let notice: UndoNotice
    let dismiss: () -> Void

    var body: some View {
        // A plain status line: it happened; «Вернуть» is there for a slip.
        HStack(spacing: MelySpace.s) {
            Image(systemName: "trash").font(.system(size: MelyType.caption, weight: .semibold))
                .foregroundStyle(.white.opacity(MelyInk.tertiary))
            Text(notice.text).font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.secondary))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Button("Вернуть") {
                notice.undo()
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: MelyType.footnote, weight: .medium))
            .foregroundStyle(.white.opacity(MelyInk.strong))
            .underline()
            .fixedSize()
            .layoutProbe("tasks.undo.button", inside: "tasks.undo", checksWhole: true)
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - Filters

private struct TaskFilterBar: View {
    @Binding var filter: TaskFilter
    let lists: [TaskList]
    let tags: [String]

    var body: some View {
        HStack(spacing: MelySpace.s) {
            HStack(spacing: 2) {
                ForEach(TaskFilter.Period.allCases, id: \.self) { period in
                    Button(period.title) { filter.period = period }
                        .buttonStyle(.plain)
                        .font(.system(size: MelyType.footnote, weight: filter.period == period ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(filter.period == period ? MelyInk.primary : MelyInk.secondary))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(.white.opacity(filter.period == period ? MelyFill.selected : 0), in: Capsule())
                        .fixedSize()
                }
            }
            .padding(2)
            .background(.white.opacity(MelyFill.card), in: Capsule())
            .layoutProbe("tasks.filters.period", row: "tasks.filters", checksWhole: true)
            Spacer(minLength: 4)
            if lists.count > 1 {
                Menu {
                    Button("Все списки") { filter.listId = nil }
                    Divider()
                    ForEach(lists) { list in Button(list.title) { filter.listId = list.id } }
                } label: {
                    chip(chipText(lists.first { $0.id == filter.listId }?.title ?? "Все списки"), symbol: "list.bullet")
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .layoutProbe("tasks.filters.list", row: "tasks.filters")
            }
            if let tag = filter.tag {
                Button { filter.tag = nil } label: {
                    HStack(spacing: 3) {
                        Text("#" + chipText(tag)).lineLimit(1)
                        Image(systemName: "xmark").font(.system(size: MelyType.micro, weight: .bold))
                    }
                    .font(.system(size: MelyType.footnote, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(MelyFill.selected), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Сбросить тег")
                .layoutProbe("tasks.filters.tag", row: "tasks.filters")
            } else if !tags.isEmpty {
                Menu {
                    ForEach(tags, id: \.self) { tag in Button("#\(tag)") { filter.tag = tag } }
                } label: { chip("#", symbol: nil) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Фильтр по тегу")
                .layoutProbe("tasks.filters.tag", row: "tasks.filters")
            }
        }
    }

    private func chip(_ title: String, symbol: String?) -> some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: MelyType.micro, weight: .semibold)) }
            Text(title).lineLimit(1)
        }
        .font(.system(size: MelyType.footnote))
        .foregroundStyle(.white.opacity(MelyInk.strong))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.white.opacity(MelyFill.card), in: Capsule())
    }
}

// MARK: - Row

private struct TaskRow<MenuItems: View>: View {
    let item: TaskItem
    let now: Date
    let showsList: Bool
    let toggle: () -> Void
    let openEditor: () -> Void
    let filterTag: (String) -> Void
    @ViewBuilder let menu: () -> MenuItems
    @State private var hovering = false

    var body: some View {
        let overdue = !item.isCompleted && item.due?.isOverdue(now: now) == true
        HStack(alignment: .top, spacing: MelySpace.m) {
            TaskCheck(done: item.isCompleted, action: toggle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if item.priority != .none {
                        Text(item.priority.marks).font(.system(size: MelyType.body, weight: .bold))
                            .foregroundStyle(MelyTint.approval).fixedSize()
                    }
                    Text(item.title).font(.system(size: MelyType.body, weight: .medium))
                        .strikethrough(item.isCompleted)
                        .lineLimit(1).truncationMode(.tail)
                }
                let due = item.due.flatMap { TaskBoard.rowLabel($0, now: now) }
                if due != nil || item.estimate != nil || !item.tags.isEmpty || showsList {
                    HStack(spacing: 5) {
                        if let due {
                            Text(due).foregroundStyle(overdue ? MelyTint.error : .white.opacity(MelyInk.secondary)).fixedSize()
                        }
                        if let estimate = item.estimate {
                            Text(estimate.label).foregroundStyle(.white.opacity(MelyInk.secondary)).fixedSize()
                        }
                        ForEach(item.tags, id: \.self) { tag in
                            Button("#\(tag)") { filterTag(tag) }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white.opacity(MelyInk.strong))
                                .lineLimit(1)
                                .help("Показать задачи с #\(tag)")
                        }
                        if showsList {
                            Text(item.listTitle).foregroundStyle(.white.opacity(MelyInk.tertiary)).lineLimit(1)
                        }
                    }
                    .font(.system(size: MelyType.caption))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: openEditor)
            Menu { menu() } label: {
                Image(systemName: "ellipsis").font(.system(size: MelyType.footnote, weight: .bold))
                    .foregroundStyle(.white.opacity(MelyInk.secondary))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .opacity(hovering ? 1 : 0)
            .help("Ещё")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.white.opacity(hovering ? MelyFill.raised : MelyFill.card), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
        .opacity(item.isCompleted ? 0.45 : 1)
        .onHover { hovering = $0 }
        .contextMenu { menu() }
    }
}

private struct TaskCheck: View {
    let done: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(done ? MelyTint.done : .white.opacity(MelyInk.secondary))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(done ? "Вернуть в невыполненные" : "Выполнено")
    }
}

/// The «⋯» and right-click menu: move it, or delete it.
private struct TaskMenu: View {
    let item: TaskItem
    let now: Date
    let actions: TasksActions
    let pickDate: () -> Void
    let delete: () -> Void

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        Button("На сегодня") { actions.moveToDay(item.id, today) }
        Button("На завтра") { actions.moveToDay(item.id, cal.date(byAdding: .day, value: 1, to: today) ?? today) }
        Button("На понедельник") { actions.moveToDay(item.id, Self.nextMonday(after: today, calendar: cal)) }
        Button("Выбрать дату…", action: pickDate)
        Button("Без срока") { actions.setDue(item.id, nil) }
        Divider()
        Button("Открыть в Напоминаниях") { actions.open(item.id) }
        Button("Удалить", role: .destructive, action: delete)
    }

    static func nextMonday(after day: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: day)
        let ahead = (2 - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: ahead == 0 ? 7 : ahead, to: day) ?? day
    }
}

// MARK: - Editor

/// A task opened in its row: everything about it, saved as it changes.
private struct TaskEditor: View {
    let item: TaskItem
    let lists: [TaskList]
    let tags: [String]
    let now: Date
    let tabs: IslandTabs
    let actions: TasksActions
    let close: () -> Void
    let delete: () -> Void

    @State private var title = ""
    @State private var newTag = ""
    @State private var pickingDate = false
    @State private var pickingTime = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let monday = TaskMenu.nextMonday(after: today, calendar: cal)
        VStack(alignment: .leading, spacing: MelySpace.s) {
            HStack(spacing: MelySpace.m) {
                TaskCheck(done: item.isCompleted) { actions.setCompleted(item.id, !item.isCompleted) }
                TextField("Название", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: MelyType.body, weight: .medium))
                    .focused($titleFocused)
                    .onSubmit(saveTitle)
                    .onChange(of: titleFocused) { if !titleFocused { saveTitle() } }
                Button(action: close) {
                    Image(systemName: "chevron.up").font(.system(size: MelyType.footnote, weight: .bold))
                        .foregroundStyle(.white.opacity(MelyInk.secondary))
                }
                .buttonStyle(.plain)
                .help("Свернуть")
            }
            HStack(spacing: 4) {
                chip("Сегодня", on: item.due?.dayStart() == today) { actions.moveToDay(item.id, today) }
                chip("Завтра", on: item.due?.dayStart() == tomorrow) { actions.moveToDay(item.id, tomorrow) }
                chip("Пн", on: item.due?.dayStart() == monday) { actions.moveToDay(item.id, monday) }
                let otherDay = item.due.map { $0.dayStart() }.flatMap { [today, tomorrow, monday].contains($0) ? nil : $0 }
                chip(otherDay.map { TaskBoard.dayLabel($0, now: now, calendar: cal) } ?? "", symbol: "calendar", on: otherDay != nil) {
                    pickingDate = true
                }
                .help("Выбрать дату")
                .popover(isPresented: $pickingDate, arrowEdge: .bottom) {
                    DuePicker(initial: item.due?.date() ?? today, time: false) { date in
                        actions.moveToDay(item.id, date)
                        pickingDate = false
                    }
                }
                chip(timeLabel, symbol: "clock", on: item.due?.hasTime == true) { pickingTime = true }
                    .help("Время")
                    .popover(isPresented: $pickingTime, arrowEdge: .bottom) {
                        DuePicker(initial: item.due?.hasTime == true ? item.due!.date() : today.addingTimeInterval(10 * 3600),
                                  time: true, clear: item.due?.hasTime == true ? { setTime(nil) } : nil) { date in
                            setTime(date)
                            pickingTime = false
                        }
                    }
                chip("Без срока", on: false) { actions.setDue(item.id, nil) }
                    .opacity(item.due == nil ? 0.4 : 1)
                    .disabled(item.due == nil)
            }
            .layoutProbe("tasks.editor.due", row: "tasks.editor.due", inside: "tasks.editor")
            HStack(spacing: 4) {
                ForEach(TaskPriority.allCases, id: \.self) { p in
                    chip(p == .none ? "—" : p.marks, on: item.priority == p) { actions.setPriority(item.id, p) }
                        .help(Self.priorityHelp(p))
                }
                Menu {
                    ForEach(TaskEstimate.allCases, id: \.self) { e in
                        Button(e.label) { actions.setMarks(item.id, TaskMarks(tags: item.tags, estimate: e)) }
                    }
                    Divider()
                    Button("Без оценки") { actions.setMarks(item.id, TaskMarks(tags: item.tags)) }
                } label: { chipLabel(item.estimate?.label ?? "оценка", symbol: "timer", on: item.estimate != nil) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                if lists.count > 1 {
                    Menu {
                        ForEach(lists) { list in Button(list.title) { actions.moveToList(item.id, list.id) } }
                    } label: { chipLabel(chipText(item.listTitle), symbol: "list.bullet", on: false) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
            }
            // Long tags scroll sideways instead of widening the island.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(item.tags, id: \.self) { tag in
                        Button {
                            actions.setMarks(item.id, TaskMarks(tags: item.tags.filter { $0 != tag }, estimate: item.estimate))
                        } label: {
                            HStack(spacing: 3) {
                                Text("#" + chipText(tag)).lineLimit(1)
                                Image(systemName: "xmark").font(.system(size: MelyType.micro, weight: .bold))
                            }
                            .modifier(ChipStyle(on: true))
                        }
                        .buttonStyle(.plain)
                    }
                    TextField("+ тег", text: $newTag)
                        .textFieldStyle(.plain)
                        .font(.system(size: MelyType.footnote))
                        .frame(width: 70)
                        .onSubmit { addTag(newTag) }
                    ForEach(tags.filter { t in !item.tags.contains(t) && (newTag.isEmpty || t.lowercased().hasPrefix(newTag.lowercased())) }
                        .prefix(3), id: \.self) { tag in
                        chip("#" + chipText(tag), on: false) { addTag(tag) }
                            .opacity(0.7)
                    }
                }
            }
            .layoutProbe("tasks.editor.tags", inside: "tasks.editor")
            HStack {
                Button("Открыть в Напоминаниях") { actions.open(item.id) }
                    .buttonStyle(.plain)
                    .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.secondary))
                    .fixedSize()
                Spacer(minLength: 4)
                Button("Удалить", role: .destructive, action: delete)
                    .buttonStyle(.plain)
                    .font(.system(size: MelyType.caption, weight: .semibold)).foregroundStyle(MelyTint.error)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(.white.opacity(MelyFill.raised), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
        .onAppear {
            title = item.title
            // Escape folds the task, dropping an unsaved name; the island stays open.
            tabs.escape = {
                title = item.title
                close()
            }
        }
        .onDisappear { tabs.escape = nil }
        .onChange(of: item.title) { if !titleFocused { title = item.title } }
    }

    private var timeLabel: String {
        if case let .time(date)? = item.due { return date.formatted(date: .omitted, time: .shortened) }
        return ""
    }

    private func saveTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty name is a slip, not a rename.
        guard !trimmed.isEmpty else { title = item.title; return }
        if trimmed != item.title { actions.rename(item.id, trimmed) }
    }

    /// A time on the task's day (today when it has none); nil keeps the day.
    private func setTime(_ date: Date?) {
        let cal = Calendar.current
        let day = item.due?.dayStart() ?? cal.startOfDay(for: now)
        guard let date else {
            actions.setDue(item.id, .day(of: day))
            pickingTime = false
            return
        }
        let t = cal.dateComponents([.hour, .minute], from: date)
        if let at = cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) {
            actions.setDue(item.id, .time(at))
        }
    }

    private func addTag(_ tag: String) {
        let tag = tag.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))
        newTag = ""
        guard !tag.isEmpty else { return }
        actions.setMarks(item.id, TaskMarks(tags: item.tags + [tag], estimate: item.estimate))
    }

    static func priorityHelp(_ p: TaskPriority) -> String {
        switch p {
        case .none: "Без приоритета"
        case .low: "Низкий приоритет"
        case .medium: "Средний приоритет"
        case .high: "Высокий приоритет"
        }
    }

    private func chip(_ title: String, symbol: String? = nil, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, symbol: symbol, on: on) }.buttonStyle(.plain)
    }

    private func chipLabel(_ title: String, symbol: String? = nil, on: Bool) -> some View {
        ChipLabel(title: title, symbol: symbol, on: on)
    }
}

/// A chip's text with an optional symbol before it.
struct ChipLabel: View {
    let title: String
    var symbol: String?
    let on: Bool

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: MelyType.caption, weight: .semibold)) }
            if !title.isEmpty { Text(title).lineLimit(1) }
        }
        .modifier(ChipStyle(on: on))
    }
}

/// A list or tag name in a chip: long ones end in "…" so the chip never widens the island.
func chipText(_ text: String, max: Int = 18) -> String {
    text.count <= max ? text : String(text.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
}

struct ChipStyle: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: MelyType.footnote, weight: on ? .semibold : .regular))
            .foregroundStyle(.white.opacity(on ? MelyInk.primary : MelyInk.strong))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.white.opacity(on ? MelyFill.selected : MelyFill.card), in: Capsule())
            .fixedSize()
    }
}

/// A date (or a time) in a popover.
private struct DuePicker: View {
    let time: Bool
    let clear: (() -> Void)?
    let pick: (Date) -> Void
    @State private var date: Date

    init(initial: Date, time: Bool, clear: (() -> Void)? = nil, pick: @escaping (Date) -> Void) {
        self.time = time
        self.clear = clear
        self.pick = pick
        _date = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if time {
                DatePicker("Время", selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
            } else {
                DatePicker("Дата", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
            }
            HStack {
                if let clear { Button("Убрать время", action: clear) }
                Spacer()
                Button("Готово") { pick(date) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: time ? 220 : 260)
    }
}

// MARK: - «+ Задача»

/// The line at the bottom: typed text recognized on the fly, chips for those who click.
private struct QuickTaskLine: View {
    @Binding var draft: QuickTaskDraft
    let tabs: IslandTabs
    let filter: TaskFilter
    let lists: [TaskList]
    let tags: [String]
    let now: Date
    let create: (QuickTask) -> Void
    @FocusState private var focused: Bool
    @State private var pickingDate = false

    var body: some View {
        let preview = draft.preview(filter: filter, now: now)
        VStack(alignment: .leading, spacing: 5) {
            // A field, not a button: an outline like the chat's input, no "+".
            HStack(spacing: MelySpace.m) {
                TextField("Новая задача", text: Binding(get: { draft.text }, set: { draft.setText($0) }))
                    .textFieldStyle(.plain)
                    .font(.system(size: MelyType.body))
                    .focused($focused)
                    .onSubmit(save)
                if !draft.text.isEmpty {
                    Image(systemName: "return").font(.system(size: MelyType.caption, weight: .semibold))
                        .foregroundStyle(.white.opacity(MelyInk.tertiary))
                        .help("Enter — добавить")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: MelyRadius.medium)
                .strokeBorder(.white.opacity(focused ? 0.25 : MelyFill.border)))
            .onChange(of: focused) {
                // Escape clears the line and leaves it; the island stays open.
                tabs.escape = focused ? {
                    draft.reset()
                    focused = false
                } : nil
            }
            if focused || !draft.text.isEmpty {
                if draft.text.isEmpty {
                    Text("Пишите как удобно: «завтра в 10», «в пт», !!, #тег, ~30м")
                        .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .layoutProbe("tasks.add.hint", inside: "tasks.add", checksText: true)
                } else {
                    // Everything recognized at once can be wider than the island: it scrolls sideways.
                    ScrollView(.horizontal, showsIndicators: false) { chips(preview) }
                        .layoutProbe("tasks.add.chips", inside: "tasks.add")
                }
            }
        }
    }

    private func chips(_ preview: QuickTask) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let day = preview.due?.dayStart()
        return HStack(spacing: 4) {
            chip("Сегодня", on: day == today) { draft.setDue(.day(of: today)) }
            chip("Завтра", on: day == tomorrow) { draft.setDue(.day(of: tomorrow)) }
            let other = preview.due.flatMap { d in d.dayStart() == today || d.dayStart() == tomorrow ? nil : d }
            Button { pickingDate = true } label: {
                ChipLabel(title: other.map { TaskBoard.dayLabel($0.dayStart(), now: now) } ?? "", symbol: "calendar", on: other != nil)
            }
            .buttonStyle(.plain)
            .help("Выбрать дату")
                .popover(isPresented: $pickingDate, arrowEdge: .bottom) {
                    DuePicker(initial: preview.due?.date() ?? today, time: false) { date in
                        draft.setDue(.day(of: date))
                        pickingDate = false
                    }
                }
            if let due = preview.due, due.hasTime {
                ChipLabel(title: TaskBoard.label(due, now: now).components(separatedBy: ", ").last!, symbol: "clock", on: true)
            }
            Menu {
                ForEach(tags, id: \.self) { tag in Button("#\(tag)") { draft.addTag(tag) } }
                if !preview.tags.isEmpty {
                    Divider()
                    ForEach(preview.tags, id: \.self) { tag in Button("Убрать #\(tag)") { draft.removeTag(tag) } }
                }
            } label: {
                Text(preview.tags.isEmpty ? "#" : chipText(preview.tags.map { "#" + $0 }.joined(separator: " "), max: 24))
                    .lineLimit(1).modifier(ChipStyle(on: !preview.tags.isEmpty))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            Menu {
                ForEach(TaskEstimate.allCases, id: \.self) { e in Button(e.label) { draft.setEstimate(e) } }
                Divider()
                Button("Без оценки") { draft.setEstimate(nil) }
            } label: {
                ChipLabel(title: preview.estimate?.label ?? "", symbol: "timer", on: preview.estimate != nil)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            Menu {
                ForEach(TaskPriority.allCases, id: \.self) { p in
                    Button(p == .none ? "Без приоритета" : p.marks) { draft.setPriority(p) }
                }
            } label: {
                Text(preview.priority == .none ? "!" : preview.priority.marks).modifier(ChipStyle(on: preview.priority != .none))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Приоритет")
            if lists.count > 1 {
                Menu {
                    ForEach(lists) { list in Button(list.title) { draft.setList(list.id) } }
                } label: {
                    Text(chipText(lists.first { $0.id == preview.listId }?.title ?? "Список")).lineLimit(1)
                        .modifier(ChipStyle(on: preview.listId != nil))
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).lineLimit(1).modifier(ChipStyle(on: on)) }.buttonStyle(.plain)
    }

    private func save() {
        guard let task = draft.resolved(filter: filter, now: now) else { return }
        create(task)
        draft.reset()
    }
}
