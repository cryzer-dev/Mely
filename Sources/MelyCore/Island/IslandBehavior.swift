import Foundation
import Observation

/// Settings → Основные (task 7.11): how the island opens and folds, the sounds, the launch
/// greeting. Each value lives under its own UserDefaults key.
@MainActor
@Observable
public final class IslandBehavior {
    public enum Keys {
        public static let openOnHover = "islandOpenOnHover"
        public static let collapseAfter = "islandCollapseAfter"
        public static let hideAfter = "islandHideAfter"
        public static let collapseOnFocusLoss = "islandCollapseOnFocusLoss"
        public static let launchGreeting = "launchGreeting"
        public static let soundOn = "soundOn"
        public static let soundVolume = "soundVolume"
    }

    /// «Закрывать панель»: seconds after the pointer leaves; `never` keeps it open until
    /// «×» or Esc.
    public static let collapseChoices: [TimeInterval] = [3, 5, 15, 30, 60, never]
    /// «Убирать полоску выреза»: seconds without events before only the notch is left.
    public static let hideChoices: [TimeInterval] = [30, 60, 180, 300, never]
    public static let never: TimeInterval = 0

    @ObservationIgnored private let defaults: UserDefaults
    /// Any value changed: the app re-applies them.
    @ObservationIgnored public var onChange: (() -> Void)?

    /// Hovering opens the island (folds again shortly after the pointer leaves).
    public var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: Keys.openOnHover); onChange?() } }
    public var collapseAfter: TimeInterval { didSet { defaults.set(collapseAfter, forKey: Keys.collapseAfter); onChange?() } }
    public var hideAfter: TimeInterval { didSet { defaults.set(hideAfter, forKey: Keys.hideAfter); onChange?() } }
    /// «Закрывать при клике мимо»: a click outside Mely or another app coming forward folds the panel.
    public var collapseOnFocusLoss: Bool {
        didSet { defaults.set(collapseOnFocusLoss, forKey: Keys.collapseOnFocusLoss); onChange?() }
    }
    /// Mely peeks out of the notch at launch.
    public var launchGreeting: Bool { didSet { defaults.set(launchGreeting, forKey: Keys.launchGreeting); onChange?() } }
    public var soundOn: Bool { didSet { defaults.set(soundOn, forKey: Keys.soundOn); onChange?() } }
    /// 0…1.
    public var soundVolume: Double { didSet { defaults.set(soundVolume, forKey: Keys.soundVolume); onChange?() } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        openOnHover = defaults.bool(forKey: Keys.openOnHover)
        collapseAfter = defaults.object(forKey: Keys.collapseAfter) as? Double ?? 5
        hideAfter = defaults.object(forKey: Keys.hideAfter) as? Double ?? 60
        collapseOnFocusLoss = defaults.object(forKey: Keys.collapseOnFocusLoss) as? Bool ?? true
        launchGreeting = defaults.object(forKey: Keys.launchGreeting) as? Bool ?? true
        soundOn = defaults.object(forKey: Keys.soundOn) as? Bool ?? true
        soundVolume = defaults.object(forKey: Keys.soundVolume) as? Double ?? 0.5
    }

    /// Hands the timing over to the island's state machine.
    public func apply(to machine: IslandStateMachine) {
        machine.openOnHover = openOnHover
        machine.collapsesWhenLeft = collapseAfter != Self.never
        if collapseAfter != Self.never { machine.expandedToCompactDelay = collapseAfter }
        machine.collapsesOnFocusLoss = collapseOnFocusLoss
        machine.hidesWhenIdle = hideAfter != Self.never
        if hideAfter != Self.never { machine.compactToHiddenDelay = hideAfter }
    }

    public static func title(collapse seconds: TimeInterval) -> String {
        seconds == never ? "Не закрывать" : "Через \(Int(seconds)) с"
    }

    public static func title(hide seconds: TimeInterval) -> String {
        if seconds == never { return "Не убирать" }
        return seconds < 60 ? "Через \(Int(seconds)) с" : "Через \(Int(seconds / 60)) мин"
    }
}
