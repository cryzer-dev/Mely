import SwiftUI
import AppKit
import MelyCore

/// Settings → Основные (task 7.11): how the island behaves, where it lives, its sounds and
/// what happens at launch.
public struct GeneralSettingsView: View {
    let behavior: IslandBehavior
    let sounds: Sounds
    /// Launch at login, through the system (SMAppService).
    let launchAtLogin: Binding<Bool>
    /// The island moves at once when the screen choice changes.
    let displayChanged: () -> Void
    /// Settings → Обновления; nil hides the section.
    let updates: UpdateState?
    /// Previews of new tracks; nil hides the music section.
    let peeks: NowPlayingPeeks?

    /// What the sound section can do; the app plays and finds the files.
    public struct Sounds {
        public var test: () -> Void
        public var openFolder: () -> Void
        public var reload: () -> Int
        public var customized: Int
        public init(test: @escaping () -> Void, openFolder: @escaping () -> Void, reload: @escaping () -> Int, customized: Int) {
            self.test = test
            self.openFolder = openFolder
            self.reload = reload
            self.customized = customized
        }
    }

    @AppStorage(IslandWings.Mode.defaultsKey) private var wingsMode: IslandWings.Mode = .default
    @AppStorage(IslandDisplayChoice.defaultsKey) private var display = IslandDisplayChoice.notch.storageValue
    @State private var customized: Int
    @AppStorage(CharacterQuirks.birthdayKey) private var birthdayString = ""

    /// The stored "MM-dd" as a date this year, for the picker.
    private var birthday: Date? {
        guard let day = CharacterQuirks.birthday(from: birthdayString) else { return nil }
        var c = Calendar.current.dateComponents([.year], from: Date())
        c.month = day.month
        c.day = day.day
        return Calendar.current.date(from: c)
    }

    private static func fullScreenHint(_ mode: FullScreenMode) -> String {
        switch mode {
        case .normal: "Челка и Mely видны поверх видео, игр и презентаций"
        case .importantOnly: "Поверх видео, игр и презентаций — только запросы разрешений и вопросы Claude, остальное прячется и молчит"
        case .doNotDisturb: "Поверх видео, игр и презентаций — ничего; запросы ждут в челке, пока не выйдешь из полноэкранного режима"
        }
    }

    private static func store(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        return String(format: "%02d-%02d", c.month ?? 1, c.day ?? 1)
    }

    public init(behavior: IslandBehavior, sounds: Sounds, launchAtLogin: Binding<Bool>, updates: UpdateState? = nil,
                peeks: NowPlayingPeeks? = nil, displayChanged: @escaping () -> Void) {
        self.behavior = behavior
        self.updates = updates
        self.peeks = peeks
        self.sounds = sounds
        self.launchAtLogin = launchAtLogin
        self.displayChanged = displayChanged
        _customized = State(initialValue: sounds.customized)
    }

    public var body: some View {
        @Bindable var behavior = behavior
        Form {
            Section {
                // «Панель» — the open island with tabs; «полоска выреза» — Mely and the status
                // beside the notch. Each setting says under it what it does.
                Toggle(isOn: $behavior.openOnHover) {
                    Text("Открывать при наведении")
                    Text("Панель открывается, когда курсор над вырезом, а не по клику")
                }
                Picker(selection: $behavior.collapseAfter) {
                    ForEach(IslandBehavior.collapseChoices, id: \.self) { Text(IslandBehavior.title(collapse: $0)).tag($0) }
                } label: {
                    Text("Закрывать панель")
                    Text("Через сколько после ухода курсора панель сворачивается в полоску выреза")
                }
                Toggle(isOn: $behavior.collapseOnFocusLoss) {
                    Text("Закрывать при клике мимо")
                    Text("Клик в другом окне или переход в другое приложение сразу сворачивает панель")
                }
                Picker(selection: $behavior.hideAfter) {
                    ForEach(IslandBehavior.hideChoices, id: \.self) { Text(IslandBehavior.title(hide: $0)).tag($0) }
                } label: {
                    Text("Убирать полоску выреза")
                    Text("Через сколько без событий полоска прячется и остаётся только вырез")
                }
                Picker(selection: $wingsMode) {
                    ForEach(IslandWings.Mode.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Полоска закрывает значки строки меню")
                    Text("Когда полоска выреза видна поверх значков рядом с вырезом")
                }
            } header: {
                Text("Поведение")
            } footer: {
                Text("Пока ждёт разрешение или вопрос Claude, панель открыта всегда: закрыть её можно «×» в шапке или Esc.")
                    .foregroundStyle(.secondary)
            }

            Section("Экран") {
                Picker("Где показывать челку", selection: Binding(get: { display }, set: { display = $0; displayChanged() })) {
                    Text("Экран с вырезом").tag(IslandDisplayChoice.notch.storageValue)
                    Text("Главный экран (со строкой меню)").tag(IslandDisplayChoice.menuBar.storageValue)
                    Text("Следовать за курсором").tag(IslandDisplayChoice.followMouse.storageValue)
                }
                Picker(selection: $behavior.fullScreenMode) {
                    ForEach(FullScreenMode.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Полноэкранные приложения")
                    Text(Self.fullScreenHint(behavior.fullScreenMode))
                }
            }

            if let peeks { MusicPeeksSection(peeks: peeks) }

            Section {
                Toggle("Звуки", isOn: $behavior.soundOn)
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $behavior.soundVolume, in: 0...1) { editing in if !editing { sounds.test() } }.labelsHidden()
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    Text("\(Int(behavior.soundVolume * 100)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                .disabled(!behavior.soundOn)
                HStack {
                    Button("Проверить", action: sounds.test)
                    Button("Папка своих звуков", action: sounds.openFolder)
                    Button("Перечитать") { customized = sounds.reload(); sounds.test() }
                    Spacer()
                    if customized > 0 { Text("своих: \(customized)").foregroundStyle(.secondary) }
                }
                .disabled(!behavior.soundOn)
            } header: {
                Text("Звук")
            } footer: {
                Text("Готово, разрешение, вопрос, ошибка, лимит, файл в челке. В режиме фокусировки тихо. Чтобы заменить звук, положи в папку файл с тем же именем (finish.wav, approval.m4a, greet.mp3…) и нажми «Перечитать».")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Знает мой день рождения", isOn: Binding(get: { birthday != nil },
                                                               set: { birthdayString = $0 ? Self.store(Date()) : "" }))
                if let date = birthday {
                    DatePicker("День рождения", selection: Binding(get: { date }, set: { birthdayString = Self.store($0) }),
                               displayedComponents: .date)
                }
            } header: {
                Text("Mely")
            } footer: {
                Text("Иногда подмигивает, а по особым дням — вечер пятницы, Новый год, твой день рождения — устраивает маленький салют. Не чаще раза в несколько минут и только когда ничего не ждёт ответа.")
                    .foregroundStyle(.secondary)
            }

            Section("Запуск") {
                Toggle("Mely здоровается при запуске", isOn: $behavior.launchGreeting)
                Toggle("Запускать при входе в систему", isOn: launchAtLogin)
            }

            if let updates { UpdatesSection(updates: updates) }
        }
        .formStyle(.grouped)
    }
}

/// Settings → Основные → Обновления, laid out as Sparkle apps on the Mac do: the icon and
/// the version with its state, one main button, the switch, and the links to what changed.
public struct UpdatesSection: View {
    let updates: UpdateState

    public init(updates: UpdateState) { self.updates = updates }

    public var body: some View {
        @Bindable var updates = updates
        Section {
            HStack(spacing: 12) {
                MelyAppIcon().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mely \(updates.currentVersion)").font(.headline).lineLimit(1).truncationMode(.middle)
                    if !updates.statusText.isEmpty { status }
                }
                Spacer(minLength: 8)
                if updates.hasPendingUpdate {
                    Button("Обновить", action: updates.installNow).buttonStyle(.borderedProminent)
                } else {
                    Button("Проверить сейчас", action: updates.checkNow).disabled(updates.phase == .checking)
                }
            }
            .padding(.vertical, 2)
            Toggle("Проверять автоматически", isOn: $updates.checksAutomatically)
            if let releases = updates.releasesURL {
                HStack(spacing: 20) {
                    if let notes = updates.notesURL(for: updates.currentVersion) {
                        link("Что нового в \(updates.currentVersion)", notes)
                    }
                    link("Все версии", releases)
                    Spacer(minLength: 0)
                }
            }
        } header: {
            Text("Обновления")
        } footer: {
            Text("Раз в день Mely тихо проверяет, не вышла ли новая версия.").foregroundStyle(.secondary)
        }
    }

    /// The state with its mark: a tick, a dot for a waiting version, a warning, a spinner.
    private var status: some View {
        HStack(spacing: 5) {
            switch updates.phase {
            case .checking: ProgressView().controlSize(.mini)
            case .upToDate: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .available: Circle().fill(Color.accentColor).frame(width: 7, height: 7)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            case .idle: EmptyView()
            }
            Text(updates.statusText)
                .foregroundStyle(updates.phase == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        }
        .font(.callout)
    }

    /// Opens in the browser: the link's colour and an arrow out.
    private func link(_ title: String, _ url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(.link)
        .pointerStyle(.link)
        .help(url.absoluteString)
    }
}

/// Settings → Клавиши: the shortcuts, for reference.
public struct ShortcutsSettingsView: View {
    public init() {}

    public var body: some View {
        Form {
            Section {
                row("⌃⌥Space", "Чат с Claude: челка открывается с полем ввода и окном, где ты был")
                row("⌃⌥D", "Mely на рабочий стол и обратно")
                row("Esc", "Свернуть раскрытую челку")
            } footer: {
                Text("Работают в любом приложении, разрешений не нужно.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ keys: String, _ what: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(keys).font(.system(.body, design: .rounded).weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 110, alignment: .leading)
            Text(what)
        }
    }
}

/// Settings → Основные → Музыка: previews of new tracks, all of them and per app.
struct MusicPeeksSection: View {
    let peeks: NowPlayingPeeks

    var body: some View {
        @Bindable var peeks = peeks
        Section {
            Toggle(isOn: $peeks.isOn) {
                Text("Подсказка «Сейчас играет»")
                Text("Обложка и название под челкой, когда начинается песня или видео. Пока они быстро сменяют друг друга (шортсы, перелистывание), подсказки нет")
            }
            ForEach(peeks.apps, id: \.self) { app in
                Toggle(isOn: Binding(get: { !peeks.isMuted(app) }, set: { peeks.setMuted(app, !$0) })) {
                    HStack(spacing: 8) {
                        AppIcon(bundleId: app).frame(width: 18, height: 18)
                        Text(MiniPlayerView.appName(app))
                    }
                }
                .disabled(!peeks.isOn)
            }
        } header: {
            Text("Музыка и видео")
        } footer: {
            Text(peeks.apps.isEmpty
                 ? "Здесь появятся приложения, из которых что-то играло. Подсказку для играющего приложения можно выключить и на вкладке «Музыка» — колокольчиком."
                 : "Подсказку для играющего приложения можно выключить и на вкладке «Музыка» — колокольчиком. Мини-плеер и обложка в полоске работают всегда.")
                .foregroundStyle(.secondary)
        }
    }
}
