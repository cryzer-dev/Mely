import SwiftUI
import AppKit
import MelyCore

/// The "Фокус…" window: the rhythm, what happens around a session, sounds and the shortcut.
/// Changes apply at once; lengths from the next session or break.
public struct FocusSettingsView: View {
    @Bindable var settings: FocusSettings
    /// The shortcut field starts listening (the snapshots).
    let recording: Bool
    let close: () -> Void

    public init(settings: FocusSettings, recording: Bool = false, close: @escaping () -> Void) {
        self.settings = settings
        self.recording = recording
        self.close = close
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Фокус").font(.title3.weight(.semibold))
            Text("Таймер в челке рядом с Mely. Изменённые длительности действуют со следующей сессии или перерыва.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Ритм").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                minutes("Фокус по умолчанию", $settings.defaultMinutes, in: FocusSettings.customRange, step: 5)
                minutes("Короткий перерыв", $settings.shortBreakMinutes, in: 1...30, step: 1)
                minutes("Длинный перерыв", $settings.longBreakMinutes, in: 5...60, step: 5)
                GridRow {
                    Text("Длинный перерыв после")
                    Stepper(value: $settings.longBreakEvery, in: 2...8) {
                        Text("\(settings.longBreakEvery) \(Self.sessionsWord(settings.longBreakEvery))").monospacedDigit()
                    }
                    .fixedSize()
                }
            }
            Toggle("Начинать перерыв сам", isOn: $settings.autoStartsBreak)
            Toggle("Начинать следующий фокус после перерыва", isOn: $settings.autoStartsNext)

            Text("Во время фокуса").font(.headline)
            described("Тишина во время фокуса", $settings.holdsMessages,
                      "Сообщения из «Уведомлений» не всплывают, а ждут во вкладке. В перерыве — одна сводка. Claude Code, встречи и задачи приходят как обычно.")
            described("Предупреждать о встречах", $settings.warnsMeetings,
                      "За 5 минут до встречи из календаря, если она начнётся до конца фокуса.")
            HStack(spacing: 8) {
                Toggle("Пауза, если меня нет", isOn: $settings.pausesWhenAway)
                Stepper(value: $settings.awayMinutes, in: 1...30) {
                    Text("через \(settings.awayMinutes) мин").monospacedDigit()
                }
                .fixedSize()
                .disabled(!settings.pausesWhenAway)
            }

            Text("Звуки и клавиша").font(.headline)
            Toggle("Звук в начале", isOn: $settings.playsStartSound)
            Toggle("Звук в конце", isOn: $settings.playsEndSound)
            HStack(spacing: 8) {
                Text("Начать или поставить на паузу")
                HotKeyField(hotKey: $settings.hotKey, recording: recording)
                if settings.hotKey != FocusSettings.defaultFocusHotKey {
                    Button("Сбросить") { settings.hotKey = FocusSettings.defaultFocusHotKey }
                        .buttonStyle(.link)
                }
            }

            HStack {
                Spacer()
                Button("Готово", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func minutes(_ title: String, _ value: Binding<Int>, in range: ClosedRange<Int>, step: Int) -> some View {
        GridRow {
            Text(title)
            Stepper(value: value, in: range, step: step) { Text("\(value.wrappedValue) мин").monospacedDigit() }
                .fixedSize()
        }
    }

    private func described(_ title: String, _ isOn: Binding<Bool>, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: isOn)
            Text(text).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// «4 сессий» reads wrong after «после»: «после 4 сессий», «после 2 сессий».
    static func sessionsWord(_ n: Int) -> String { n % 10 == 1 && n % 100 != 11 ? "сессии" : "сессий" }
}

public extension FocusSettings {
    static let defaultFocusHotKey = FocusHotKey(code: defaultHotKey.code, modifiers: defaultHotKey.modifiers)
}

/// The shortcut: a click, then the keys; Escape gives up. Mely's own shortcuts and a key
/// without ⌃, ⌥ or ⌘ are refused with the reason.
struct HotKeyField: View {
    @Binding var hotKey: FocusHotKey
    @State private var recording: Bool
    @State private var problem: String?
    @State private var monitor: Any?

    init(hotKey: Binding<FocusHotKey>, recording: Bool = false) {
        _hotKey = hotKey
        _recording = State(initialValue: recording)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Нажми сочетание…" : hotKey.label)
                    .monospaced(!recording)
                    .frame(minWidth: 110)
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        problem = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Escape
                stop()
                return nil
            }
            let flags = event.modifierFlags
            var modifiers = 0
            if flags.contains(.control) { modifiers |= FocusHotKey.control }
            if flags.contains(.option) { modifiers |= FocusHotKey.option }
            if flags.contains(.shift) { modifiers |= FocusHotKey.shift }
            if flags.contains(.command) { modifiers |= FocusHotKey.command }
            let key = FocusHotKey(code: Int(event.keyCode), modifiers: modifiers)
            if let problem = key.problem {
                self.problem = problem
            } else {
                hotKey = key
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
