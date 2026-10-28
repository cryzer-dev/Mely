import SwiftUI
import MelyCore

/// What the focus card and the picker can ask for; the app fills it from `FocusIntegration`.
public struct FocusActions {
    public var pause: () -> Void = {}
    public var resume: () -> Void = {}
    /// «+5 мин» while running, «Ещё 10 мин» after the end.
    public var extend: (Int) -> Void = { _ in }
    public var stop: () -> Void = {}
    public var takeBreak: () -> Void = {}
    public var skipBreak: () -> Void = {}
    public var continueFocus: () -> Void = {}

    public init() {}
}

// MARK: - The wing

/// The left wing while a focus runs, in the cover's place: Mely, a small progress ring and
/// the time left. A break is teal with a cup in the ring; a pause greys it and stills the time.
public struct FocusRingView<Mely: View>: View {
    let timer: FocusTimer
    let now: Date
    let mely: Mely

    public init(timer: FocusTimer, now: Date, @ViewBuilder mely: () -> Mely) {
        self.timer = timer
        self.now = now
        self.mely = mely()
    }

    private var tint: Color { timer.phase == .onBreak ? MelyTint.rest : MelyTint.focus }

    public var body: some View {
        HStack(spacing: 4) {
            mely
            FocusRing(progress: timer.progress(now: now), tint: timer.isPaused ? .white.opacity(MelyInk.secondary) : tint)
                .overlay {
                    if timer.isPaused || timer.phase == .onBreak {
                        Image(systemName: timer.isPaused ? "pause.fill" : "cup.and.saucer.fill")
                            .font(.system(size: timer.isPaused ? 5 : 5.5, weight: .black))
                            .foregroundStyle(timer.isPaused ? .white.opacity(MelyInk.strong) : tint)
                    }
                }
                .frame(width: 12, height: 12)
            Text(FocusTimer.clock(timer.remaining(now: now)))
                .font(.system(size: MelyType.footnote, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(timer.isPaused ? .white.opacity(MelyInk.secondary) : tint)
                .lineLimit(1)
                .fixedSize()
                .layoutProbe("focus.wing.time", inside: "compact.leading", checksWhole: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        let clock = FocusTimer.clock(timer.remaining(now: now))
        if timer.phase == .onBreak { return "Перерыв, осталось \(clock)" }
        return timer.isPaused ? "Фокус на паузе, осталось \(clock)" : "Фокус, осталось \(clock)"
    }
}

/// The progress ring.
struct FocusRing: View {
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// The wing, ticking once a second.
public struct CompactFocus<Mely: View>: View {
    let model: FocusModel
    let mely: Mely

    public init(model: FocusModel, @ViewBuilder mely: () -> Mely) {
        self.model = model
        self.mely = mely()
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            FocusRingView(timer: model.timer, now: context.date) { mely }
        }
    }
}

// MARK: - The card under Mely

/// Under the big Mely while a focus runs: the task, the time, «Пауза» / «Продолжить»,
/// «+5 мин», «Стоп». On a break: the time and «Пропустить»; once over, what is next.
public struct FocusCard: View {
    let timer: FocusTimer
    let now: Date
    let actions: FocusActions

    public init(timer: FocusTimer, now: Date, actions: FocusActions) {
        self.timer = timer
        self.now = now
        self.actions = actions
    }

    /// Shown for these phases; idle has no card.
    public static func shows(_ timer: FocusTimer) -> Bool { timer.phase != .idle }

    static let width = MelyStage.columnWidth

    public var body: some View {
        VStack(spacing: 5) {
            if let title = caption {
                Text(title)
                    .font(.system(size: MelyType.micro, weight: .medium))
                    .foregroundStyle(.white.opacity(MelyInk.secondary))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .layoutProbe("focus.card.title", inside: "focus.card", checksText: true)
            }
            Text(time)
                .font(.system(size: MelyType.headline, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(timer.isPaused ? .white.opacity(MelyInk.secondary) : tint)
                .lineLimit(1)
                .layoutProbe("focus.card.time", inside: "focus.card", checksWhole: true)
            HStack(spacing: 4) { buttons }
                .layoutProbe("focus.card.buttons", row: "focus.card.buttons", inside: "focus.card")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .frame(width: Self.width)
        .background(.white.opacity(MelyFill.card), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
        .overlay(RoundedRectangle(cornerRadius: MelyRadius.medium).strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .layoutProbe("focus.card", inside: "content")
    }

    private var tint: Color {
        switch timer.phase {
        case .onBreak, .breakOver: MelyTint.rest
        default: MelyTint.focus
        }
    }

    /// The task; on a break and after it, what the time is.
    private var caption: String? {
        switch timer.phase {
        case .onBreak: "Перерыв"
        case .finished: "Фокус окончен"
        case .breakOver: "Перерыв окончен"
        default: timer.task?.title
        }
    }

    private var time: String {
        switch timer.phase {
        case .finished: FocusTimer.clock(timer.worked)
        case .breakOver: FocusTimer.clock(0)
        default: FocusTimer.clock(timer.remaining(now: now))
        }
    }

    @ViewBuilder private var buttons: some View {
        switch timer.phase {
        case .working:
            FocusIconButton(symbol: "pause.fill", help: "Пауза", action: actions.pause)
            FocusTextButton(title: "+5", help: "Ещё 5 минут") { actions.extend(5) }
            FocusIconButton(symbol: "stop.fill", help: "Стоп: закончить без перерыва", action: actions.stop)
        case .paused:
            FocusIconButton(symbol: "play.fill", help: "Продолжить", tint: tint, action: actions.resume)
            FocusTextButton(title: "+5", help: "Ещё 5 минут") { actions.extend(5) }
            FocusIconButton(symbol: "stop.fill", help: "Стоп: закончить без перерыва", action: actions.stop)
        case .onBreak:
            FocusIconButton(symbol: "forward.end.fill", help: "Пропустить перерыв", action: actions.skipBreak)
            FocusIconButton(symbol: "play.fill", help: "Сразу продолжить", tint: tint, action: actions.continueFocus)
        case .finished:
            FocusIconButton(symbol: "cup.and.saucer.fill", help: "Перерыв", tint: tint, action: actions.takeBreak)
            FocusTextButton(title: "+10", help: "Ещё 10 минут") { actions.extend(10) }
            FocusIconButton(symbol: "xmark", help: "Хватит", action: actions.stop)
        case .breakOver:
            FocusIconButton(symbol: "play.fill", help: "Продолжить", tint: tint, action: actions.continueFocus)
            FocusIconButton(symbol: "xmark", help: "Хватит", action: actions.stop)
        case .idle:
            EmptyView()
        }
    }
}

/// The card, ticking once a second.
public struct LiveFocusCard: View {
    let model: FocusModel
    let actions: FocusActions

    public init(model: FocusModel, actions: FocusActions) {
        self.model = model
        self.actions = actions
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            FocusCard(timer: model.timer, now: context.date, actions: actions)
        }
    }
}

private struct FocusIconButton: View {
    let symbol: String
    let help: String
    var tint: Color = .white
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint.opacity(tint == .white ? MelyInk.primary : 1))
                .frame(width: 22, height: 20)
                .background(.white.opacity(hovered ? MelyFill.selected : MelyFill.raised), in: RoundedRectangle(cornerRadius: MelyRadius.small))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct FocusTextButton: View {
    let title: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: MelyType.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(MelyInk.primary))
                .frame(width: 26, height: 20)
                .background(.white.opacity(hovered ? MelyFill.selected : MelyFill.raised), in: RoundedRectangle(cornerRadius: MelyRadius.small))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Choosing the length

/// The popover of «Фокус» and «▶︎»: the last length first, then the rest, «Своё…» 5–180 min.
public struct FocusPicker: View {
    let choices: [Int]
    /// The task the session will be on, shown on top.
    let task: String?
    let start: (Int) -> Void
    @State private var custom = false
    @State private var minutes = ""
    @FocusState private var fieldFocused: Bool

    /// `typed`: opens on «Своё…» with this in the field (the snapshots).
    public init(choices: [Int], task: String? = nil, typed: String? = nil, start: @escaping (Int) -> Void) {
        self.choices = choices
        self.task = task
        self.start = start
        _custom = State(initialValue: typed != nil)
        _minutes = State(initialValue: typed ?? "")
    }

    /// What «Своё…» accepts: whole minutes in `FocusSettings.customRange`.
    public static func customMinutes(_ text: String) -> Int? {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)), FocusSettings.customRange.contains(n) else { return nil }
        return n
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.map { "Фокус: \($0)" } ?? "Фокус")
                .font(.system(size: MelyType.footnote, weight: .semibold))
                .lineLimit(2)
            HStack(spacing: 6) {
                ForEach(choices, id: \.self) { m in
                    // The first is the last one picked: one click to the usual rhythm.
                    if m == choices.first {
                        Button("\(m) мин") { start(m) }.buttonStyle(.borderedProminent).fixedSize()
                    } else {
                        Button("\(m) мин") { start(m) }.fixedSize()
                    }
                }
            }
            .controlSize(.small)
            if custom {
                HStack(spacing: 6) {
                    TextField("5–180", text: $minutes)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .focused($fieldFocused)
                        .onSubmit(startCustom)
                    Text("минут").foregroundStyle(.secondary)
                    Spacer()
                    Button("Начать", action: startCustom)
                        .keyboardShortcut(.defaultAction)
                        .disabled(Self.customMinutes(minutes) == nil)
                }
            } else {
                Button("Своё…") {
                    custom = true
                    fieldFocused = true
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
    }

    private func startCustom() {
        if let m = Self.customMinutes(minutes) { start(m) }
    }
}

/// A focus already runs: «Заменить» ends it with its time counted, «Отмена» leaves it.
public struct FocusReplaceConfirm: View {
    let current: String?
    let replace: () -> Void
    let cancel: () -> Void

    public init(current: String?, replace: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.current = current
        self.replace = replace
        self.cancel = cancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Уже идёт фокус").font(.system(size: MelyType.footnote, weight: .semibold))
            Text(current.map { "«\($0)». Его время засчитается." } ?? "Его время засчитается.")
                .font(.system(size: MelyType.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Отмена", action: cancel).keyboardShortcut(.cancelAction)
                Button("Заменить", action: replace).keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
    }
}

/// The picker, or first «Заменить» / «Отмена» while a session runs.
public struct FocusStartPopover: View {
    let running: FocusTimer?
    let choices: [Int]
    let task: String?
    /// The length picked; `replace` true when a running session is to end first.
    let start: (_ minutes: Int, _ replace: Bool) -> Void
    let cancel: () -> Void
    @State private var confirmed = false

    public init(running: FocusTimer?, choices: [Int], task: String? = nil,
                start: @escaping (Int, Bool) -> Void, cancel: @escaping () -> Void) {
        self.running = running
        self.choices = choices
        self.task = task
        self.start = start
        self.cancel = cancel
    }

    public var body: some View {
        if let running, running.isRunning, !confirmed {
            FocusReplaceConfirm(current: running.task?.title, replace: { confirmed = true }, cancel: cancel)
        } else {
            FocusPicker(choices: choices, task: task) { start($0, running?.isRunning == true) }
        }
    }
}

// MARK: - Under Mely

public extension View {
    /// The big Mely with the focus card and «Обновить» under it, the card above the pill.
    /// An overlay below the stage: it tells the island how low it reaches.
    func underMely(focus: AnyView?, update version: String?, action: @escaping () -> Void) -> some View {
        overlay(alignment: .bottom) {
            if focus != nil || version != nil {
                // Hangs from the stage's lower edge (a frame of no height there), a little up:
                // where the pill alone always sat.
                VStack(spacing: 8) {
                    if let focus { focus.transition(.scale(scale: 0.9).combined(with: .opacity)) }
                    if let version {
                        UpdatePill(version: version, action: action)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { g in
                    Color.clear.preference(key: IslandColumnHeightKey.self,
                                           value: g.frame(in: .named(IslandColumnHeightKey.space)).maxY)
                })
                .offset(y: UpdatePill.drop - UpdatePill.height)
                .frame(height: 0, alignment: .top)
            }
        }
        .animation(MelyMotion.tab, value: version)
        .animation(MelyMotion.tab, value: focus == nil)
    }
}
