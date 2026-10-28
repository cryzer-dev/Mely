import SwiftUI
import MelyCore

/// Lists to show, where new tasks go, today's tasks on the "Сегодня" tab, due reminders.
public struct TasksSettingsView: View {
    @Bindable var settings: TaskSettings
    let lists: [TaskList]
    /// Reminders' own default list, for «по умолчанию».
    let defaultList: TaskList?
    /// A setting that needs the tasks read again (lists shown, reminders on or off).
    let changed: () -> Void
    let close: () -> Void

    public init(settings: TaskSettings, lists: [TaskList], defaultList: TaskList?,
                changed: @escaping () -> Void = {}, close: @escaping () -> Void) {
        self.settings = settings
        self.lists = lists
        self.defaultList = defaultList
        self.changed = changed
        self.close = close
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Задачи").font(.title3.weight(.semibold))
            Text("Задачи берутся из Напоминаний и синхронизируются с iPhone. Теги и оценка хранятся последней строкой заметки задачи, например «#работа · ~30 мин».")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Показывать списки").font(.headline)
            if lists.isEmpty {
                Text("В Напоминаниях нет списков").foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(lists) { list in
                        Toggle(list.title, isOn: Binding(
                            get: { !settings.hiddenLists.contains(list.id) },
                            set: { on in
                                if on { settings.hiddenLists.remove(list.id) } else { settings.hiddenLists.insert(list.id) }
                            }))
                    }
                }
                .frame(height: min(180, CGFloat(lists.count) * 28 + 16))
            }

            Picker("Новые задачи — в список", selection: $settings.newTaskList) {
                Text(defaultList.map { "По умолчанию (\($0.title))" } ?? "По умолчанию").tag(String?.none)
                Divider()
                ForEach(lists) { list in Text(list.title).tag(String?.some(list.id)) }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Показывать задачи во вкладке «Сегодня»", isOn: $settings.showsInToday)
                Text("Задачи со временем — в ленте дня между встречами, остальные на сегодня — блоком под ней.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Напоминать о задачах под челкой", isOn: $settings.remindsUnderNotch)
                Text("В назначенное время — напоминание с «Готово» и «+1 ч». Баннеры самих Напоминаний под челкой тогда не повторяются.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Готово", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onChange(of: settings.hiddenLists) { changed() }
        .onChange(of: settings.remindsUnderNotch) { changed() }
    }
}
