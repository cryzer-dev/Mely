import Foundation
import Observation

/// What Settings → Обновления and the header dot show. The app's `UpdateController` drives
/// it from Sparkle; kept free of Sparkle so it can be tested and rendered in snapshots.
@MainActor
@Observable
public final class UpdateState {
    public enum Phase: Equatable, Sendable {
        case idle
        case checking
        case upToDate
        /// A version was found and is not installed yet.
        case available(version: String)
        case failed
    }

    public enum Keys {
        /// The version the island already announced: once per version.
        public static let announced = "updatePeekShownVersion"
        /// The version that ran last time: a different one means Mely was just updated.
        public static let lastLaunched = "lastLaunchedVersion"
    }

    public var phase: Phase = .idle
    /// From the bundle: «1.2.0», or «1.2.0-dev» for a local build with changes.
    public let currentVersion: String
    /// Mirrors Sparkle's automatic checks; the app sets `onChecksAutomaticallyChange`.
    public var checksAutomatically: Bool { didSet { onChecksAutomaticallyChange?(checksAutomatically) } }
    @ObservationIgnored public var onChecksAutomaticallyChange: ((Bool) -> Void)?
    /// «Проверить сейчас», «Обновить»: set by the app.
    @ObservationIgnored public var checkNow: () -> Void = {}
    @ObservationIgnored public var installNow: () -> Void = {}
    /// The releases page («Все версии»).
    public let releasesURL: URL?

    public init(currentVersion: String, checksAutomatically: Bool = true, releasesURL: URL? = nil) {
        self.currentVersion = currentVersion
        self.checksAutomatically = checksAutomatically
        self.releasesURL = releasesURL
    }

    /// What changed in `version`: its page on Releases. Nil for a local build.
    public func notesURL(for version: String) -> URL? {
        guard let releasesURL, !version.isEmpty, !version.hasSuffix("-dev") else { return nil }
        return releasesURL.appendingPathComponent("tag").appendingPathComponent("v\(version)")
    }

    /// The gear wears a dot while a found version waits.
    public var hasPendingUpdate: Bool {
        if case .available = phase { return true }
        return false
    }

    /// The found version not installed yet: «Обновить» under Mely.
    public var pendingVersion: String? {
        if case .available(let version) = phase { return version }
        return nil
    }

    /// Whether the island should tell about `version`: once per version, remembered.
    public func shouldAnnounce(_ version: String, defaults: UserDefaults = .standard) -> Bool {
        guard defaults.string(forKey: Keys.announced) != version else { return false }
        defaults.set(version, forKey: Keys.announced)
        return true
    }

    /// The version Mely was just updated to, if the last launch ran another one; remembers
    /// this launch. Nothing on the very first launch or for local `-dev` builds.
    public static func justUpdated(current: String, defaults: UserDefaults = .standard) -> String? {
        let last = defaults.string(forKey: Keys.lastLaunched)
        defaults.set(current, forKey: Keys.lastLaunched)
        guard let last, last != current, !current.hasSuffix("-dev"), !current.isEmpty else { return nil }
        return isNewer(current, than: last) ? current : nil
    }

    /// Dotted versions compared number by number; a «-dev» suffix is ignored.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// The line under «Версия» in Settings.
    public var statusText: String {
        switch phase {
        case .idle: ""
        case .checking: "Проверяем…"
        case .upToDate: "У вас последняя версия"
        case .available(let version): "Доступна \(version)"
        case .failed: "Не удалось проверить"
        }
    }
}
