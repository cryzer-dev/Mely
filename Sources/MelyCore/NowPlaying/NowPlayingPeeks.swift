import Foundation
import Observation

/// Whether a new track or video gets a preview under the notch: never while they flick by
/// (shorts, skipping), and not from apps the user silenced (on the Music tab or in
/// Settings). The mini-player and the cover in the notch strip do not ask.
@MainActor
@Observable
public final class NowPlayingPeeks {
    public enum Keys {
        public static let isOn = "nowPlayingPeek"
        public static let muted = "nowPlayingPeekMuted"
        public static let apps = "nowPlayingPeekApps"
    }

    /// Something new this soon after the last new thing is flicking through: no preview.
    public static let quietSwitch: TimeInterval = 45
    /// How many apps Settings lists.
    static let appsKept = 12

    @ObservationIgnored private let defaults: UserDefaults
    /// The track on screen (app and title) and when it began.
    @ObservationIgnored private var currentKey: String?
    @ObservationIgnored private var currentSince: Date?

    /// «Подсказка «Сейчас играет»».
    public var isOn: Bool { didSet { defaults.set(isOn, forKey: Keys.isOn) } }
    /// Apps (`NowPlaying.sourceBundleId`) whose new tracks get no preview.
    public private(set) var muted: Set<String> { didSet { defaults.set(Array(muted).sorted(), forKey: Keys.muted) } }
    /// Apps something played from, newest first: what Settings can switch.
    public private(set) var apps: [String] { didSet { defaults.set(apps, forKey: Keys.apps) } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isOn = defaults.object(forKey: Keys.isOn) as? Bool ?? true
        muted = Set(defaults.stringArray(forKey: Keys.muted) ?? [])
        apps = defaults.stringArray(forKey: Keys.apps) ?? []
    }

    public func isMuted(_ app: String) -> Bool { muted.contains(app) }

    public func setMuted(_ app: String, _ on: Bool) {
        if on { muted.insert(app) } else { muted.remove(app) }
        remember(app)
    }

    /// Called when `np` has started playing (a new track, or play after a pause): whether to
    /// show it. Keeps track of what played, so call it for every start.
    public func allows(_ np: NowPlaying, now: Date = Date()) -> Bool {
        let app = np.sourceBundleId
        remember(app)
        let key = app + "\n" + np.title
        var flicking = false
        // The same track again (play after a pause) is not something new.
        if key != currentKey {
            if let since = currentSince { flicking = now.timeIntervalSince(since) < Self.quietSwitch }
            currentKey = key
            currentSince = now
        }
        return isOn && !muted.contains(app) && !flicking
    }

    private func remember(_ app: String) {
        guard apps.first != app else { return }
        apps = Array(([app] + apps.filter { $0 != app }).prefix(Self.appsKept))
    }
}
