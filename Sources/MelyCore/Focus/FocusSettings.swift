import Foundation
import Observation

/// The "Фокус…" window. Changes apply at once; lengths from the next session or break.
@MainActor
@Observable
public final class FocusSettings {
    /// ⌃⌥P and the first choice before anything was picked.
    public var defaultMinutes: Int { didSet { save() } }
    /// The last length picked, offered first next time.
    public var lastPickedMinutes: Int? { didSet { save() } }
    public var shortBreakMinutes: Int { didSet { save() } }
    public var longBreakMinutes: Int { didSet { save() } }
    /// The long break after every N sessions in a row.
    public var longBreakEvery: Int { didSet { save() } }
    public var autoStartsBreak: Bool { didSet { save() } }
    public var autoStartsNext: Bool { didSet { save() } }
    /// Message previews from the notification mirror wait for the break.
    public var holdsMessages: Bool { didSet { save() } }
    /// «Через 5 мин — <встреча>» when a meeting starts before the end.
    public var warnsMeetings: Bool { didSet { save() } }
    public var pausesWhenAway: Bool { didSet { save() } }
    public var awayMinutes: Int { didSet { save() } }
    public var playsStartSound: Bool { didSet { save() } }
    public var playsEndSound: Bool { didSet { save() } }
    /// Carbon virtual key code and modifiers; ⌃⌥P by default.
    public var hotKeyCode: Int { didSet { save() } }
    public var hotKeyModifiers: Int { didSet { save() } }
    /// Told after every change (the shortcut is registered again).
    @ObservationIgnored public var changed: (() -> Void)?

    /// The picker's lengths, besides «Своё…».
    public static let choices = [25, 30, 40, 50]
    /// «Своё…» accepts this.
    public static let customRange = 5...180
    /// `kVK_ANSI_P`, `controlKey | optionKey`: ⌃⌥F is taken by window managers (Rectangle).
    public static let defaultHotKey = (code: 35, modifiers: FocusHotKey.control | FocusHotKey.option)

    /// The shortcut, both parts saved at once: never registered half changed.
    public var hotKey: FocusHotKey {
        get { FocusHotKey(code: hotKeyCode, modifiers: hotKeyModifiers) }
        set {
            batching = true
            hotKeyCode = newValue.code
            hotKeyModifiers = newValue.modifiers
            batching = false
            save()
        }
    }

    @ObservationIgnored private var batching = false
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "focus"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: Self.key)
        defaultMinutes = saved?["default"] as? Int ?? 25
        lastPickedMinutes = saved?["last"] as? Int
        shortBreakMinutes = saved?["short"] as? Int ?? 5
        longBreakMinutes = saved?["long"] as? Int ?? 15
        longBreakEvery = saved?["every"] as? Int ?? 4
        autoStartsBreak = saved?["autoBreak"] as? Bool ?? false
        autoStartsNext = saved?["autoNext"] as? Bool ?? false
        holdsMessages = saved?["hold"] as? Bool ?? true
        warnsMeetings = saved?["meetings"] as? Bool ?? true
        pausesWhenAway = saved?["away"] as? Bool ?? true
        awayMinutes = saved?["awayMinutes"] as? Int ?? 5
        playsStartSound = saved?["startSound"] as? Bool ?? true
        playsEndSound = saved?["endSound"] as? Bool ?? true
        hotKeyCode = saved?["keyCode"] as? Int ?? Self.defaultHotKey.code
        hotKeyModifiers = saved?["keyModifiers"] as? Int ?? Self.defaultHotKey.modifiers
    }

    /// The picker's lengths, the last picked first.
    public var pickerChoices: [Int] {
        let first = lastPickedMinutes ?? defaultMinutes
        return [first] + Self.choices.filter { $0 != first }
    }

    public var rhythm: FocusRhythm {
        FocusRhythm(shortBreak: TimeInterval(shortBreakMinutes * 60), longBreak: TimeInterval(longBreakMinutes * 60),
                    longEvery: longBreakEvery)
    }

    /// Passed as `awayAfter` to `FocusTimer.tick`; nil idle seconds when off.
    public var awayAfter: TimeInterval { TimeInterval(awayMinutes * 60) }

    private func save() {
        guard !batching else { return }
        var values: [String: Any] = [
            "default": defaultMinutes, "short": shortBreakMinutes, "long": longBreakMinutes, "every": longBreakEvery,
            "autoBreak": autoStartsBreak, "autoNext": autoStartsNext, "hold": holdsMessages, "meetings": warnsMeetings,
            "away": pausesWhenAway, "awayMinutes": awayMinutes, "startSound": playsStartSound, "endSound": playsEndSound,
            "keyCode": hotKeyCode, "keyModifiers": hotKeyModifiers,
        ]
        if let lastPickedMinutes { values["last"] = lastPickedMinutes }
        defaults.set(values, forKey: Self.key)
        changed?()
    }
}
