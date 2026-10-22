import Foundation
import Observation

/// What the system "Now Playing" reports (mediaremote-adapter's payload keys).
public struct NowPlaying: Equatable, Sendable {
    public var bundleId: String
    /// The browser behind a web player (YouTube in Chrome: Chrome's helper reports, Chrome is the parent).
    public var parentBundleId: String?
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval?
    public var elapsed: TimeInterval?
    /// When `elapsed` was measured.
    public var timestamp: Date?
    public var isPlaying: Bool
    public var rate: Double
    public var artwork: Data?
    /// Ads and some radio streams cannot be skipped.
    public var prohibitsSkip: Bool

    public init(bundleId: String, parentBundleId: String?, title: String, artist: String?, album: String?,
                duration: TimeInterval?, elapsed: TimeInterval?, timestamp: Date?, isPlaying: Bool, rate: Double,
                artwork: Data?, prohibitsSkip: Bool) {
        self.bundleId = bundleId
        self.parentBundleId = parentBundleId
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.isPlaying = isPlaying
        self.rate = rate
        self.artwork = artwork
        self.prohibitsSkip = prohibitsSkip
    }

    /// The app to show and open: the browser for web players.
    public var sourceBundleId: String { parentBundleId ?? bundleId }

    /// Has a length to move along (a live stream has none).
    public var canSeek: Bool { (duration ?? 0) > 0 }

    /// Position now, moved on by the time passed while playing.
    public func position(at now: Date = Date()) -> TimeInterval? {
        guard let elapsed else { return nil }
        guard isPlaying, let timestamp else { return elapsed }
        let p = elapsed + now.timeIntervalSince(timestamp) * (rate > 0 ? rate : 1)
        return duration.map { min(p, $0) } ?? p
    }
}

/// The adapter's `stream` output folded into the current state: a full payload
/// (`diff: false`) replaces it, a diff updates the keys it carries, `null` removes one.
public struct NowPlayingStream: Sendable {
    private var fields: [String: JSONObject] = [:]

    public init() {}

    /// Applies one line; returns the state after it (nil: nothing plays).
    public mutating func apply(line: String) -> NowPlaying?? {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              obj["type"] as? String == "data", let payload = obj["payload"] as? [String: Any] else { return .none }
        var current = (obj["diff"] as? Bool) == true ? (fields["state"]?.value ?? [:]) : [:]
        for (key, value) in payload {
            if value is NSNull { current.removeValue(forKey: key) } else { current[key] = value }
        }
        fields["state"] = JSONObject(current)
        return .some(Self.decode(current))
    }

    static func decode(_ p: [String: Any]) -> NowPlaying? {
        guard let bundleId = p["bundleIdentifier"] as? String, let title = p["title"] as? String, !title.isEmpty
        else { return nil }
        func number(_ key: String) -> Double? { (p[key] as? NSNumber)?.doubleValue }
        let artwork = (p["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
        return NowPlaying(bundleId: bundleId, parentBundleId: p["parentApplicationBundleIdentifier"] as? String,
                          title: title, artist: (p["artist"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                          album: p["album"] as? String, duration: number("duration"), elapsed: number("elapsedTime"),
                          timestamp: (p["timestamp"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) },
                          isPlaying: (p["playing"] as? Bool) ?? false, rate: number("playbackRate") ?? 0,
                          artwork: artwork, prohibitsSkip: (p["prohibitsSkip"] as? Bool) ?? false)
    }
}

/// The mini-player's state: shown while something plays and for 5 minutes after it stops.
@MainActor
@Observable
public final class NowPlayingModel {
    public private(set) var current: NowPlaying?
    /// When playback last stopped; nil while playing.
    @ObservationIgnored private var stoppedAt: Date?
    public static let hideAfter: TimeInterval = 5 * 60

    public init() {}

    /// Returns true when music starts: a new track, or play pressed after a pause
    /// (worth a glance in the notch).
    @discardableResult
    public func update(_ state: NowPlaying?, now: Date = Date()) -> Bool {
        let started = state.map { s in
            s.isPlaying && (s.title != current?.title || s.bundleId != current?.bundleId || current?.isPlaying != true)
        } ?? false
        // Paused before Mely looked: the player's own timestamp says since when.
        if state?.isPlaying == true { stoppedAt = nil } else if stoppedAt == nil { stoppedAt = min(state?.timestamp ?? now, now) }
        current = state
        return started
    }

    /// The player was asked to jump to `position`: shown there at once, not after its next
    /// report (the bar would snap back meanwhile).
    public func seek(to position: TimeInterval, now: Date = Date()) {
        guard var np = current, np.canSeek else { return }
        np.elapsed = min(max(0, position), np.duration ?? position)
        np.timestamp = now
        current = np
    }

    /// The mini-player is worth showing.
    public func isVisible(now: Date = Date()) -> Bool {
        guard current != nil else { return false }
        guard let stoppedAt else { return true }
        return now.timeIntervalSince(stoppedAt) < Self.hideAfter
    }
}

/// The adapter's `send` command ids.
public enum MediaCommand: Int, Sendable {
    case play = 0, pause = 1, togglePlayPause = 2, next = 4, previous = 5
}
