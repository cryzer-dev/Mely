import Testing
import Foundation
@testable import MelyCore

@Suite struct NowPlayingTests {
    @Test func fullThenDiffsThenNothing() throws {
        var stream = NowPlayingStream()
        let first = stream.apply(line: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"ru.yandex.desktop.music","title":"Тёплый вечер","artist":"Лампа и кот","duration":158.4,"elapsedTime":42,"timestamp":"2026-10-19T11:15:22Z","playing":true,"playbackRate":1}}"#)
        let np = try #require(first ?? nil)
        #expect(np.title == "Тёплый вечер")
        #expect(np.artist == "Лампа и кот")
        #expect(np.isPlaying)
        let t0 = try #require(np.timestamp)
        #expect(np.position(at: t0.addingTimeInterval(10)) == 52)
        // A diff: paused, the rest stays.
        let paused = try #require(stream.apply(line: #"{"type":"data","diff":true,"payload":{"playing":false,"playbackRate":0}}"#) ?? nil)
        #expect(!paused.isPlaying && paused.title == "Тёплый вечер")
        #expect(paused.position(at: t0.addingTimeInterval(100)) == 42)
        // A web player: the browser is the parent.
        let web = try #require(stream.apply(line: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.google.Chrome.helper","parentApplicationBundleIdentifier":"com.google.Chrome","title":"Lo-fi","playing":true}}"#) ?? nil)
        #expect(web.sourceBundleId == "com.google.Chrome")
        #expect(web.artist == nil)
        // Nothing plays: no keys at all.
        let none = stream.apply(line: #"{"type":"data","diff":false,"payload":{}}"#)
        #expect(none != nil && none! == nil)
        // Not a data line: ignored.
        #expect(stream.apply(line: "garbage") == nil)
    }

    @MainActor @Test func modelHidesFiveMinutesAfterStop() {
        let model = NowPlayingModel()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let song = NowPlaying(bundleId: "a", title: "Песня", isPlaying: true, rate: 1, prohibitsSkip: false)
        #expect(model.update(song, now: t0))                     // a new track
        #expect(!model.update(song, now: t0.addingTimeInterval(5)))
        var paused = song
        paused.isPlaying = false
        model.update(paused, now: t0.addingTimeInterval(10))
        #expect(model.isVisible(now: t0.addingTimeInterval(200)))
        #expect(!model.isVisible(now: t0.addingTimeInterval(10 + 301)))
        #expect(model.update(song, now: t0.addingTimeInterval(400)))   // play after a pause: a glance too
        #expect(model.isVisible(now: t0.addingTimeInterval(10_000)))
        // Paused an hour before Mely started: not shown at all.
        let fresh = NowPlayingModel()
        var old = paused
        old.timestamp = t0.addingTimeInterval(-3600)
        fresh.update(old, now: t0)
        #expect(!fresh.isVisible(now: t0))
    }
}

extension NowPlaying {
    init(bundleId: String, title: String, isPlaying: Bool, rate: Double, prohibitsSkip: Bool) {
        self.init(bundleId: bundleId, parentBundleId: nil, title: title, artist: nil, album: nil, duration: nil,
                  elapsed: nil, timestamp: nil, isPlaying: isPlaying, rate: rate, artwork: nil, prohibitsSkip: prohibitsSkip)
    }
}

/// When a new track gets a preview (openspec now-playing: «не мешает», «по приложениям»).
@MainActor
@Suite struct NowPlayingPeeksTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func peeks() -> NowPlayingPeeks {
        let suite = "mely-peeks-\(UUID().uuidString)"
        return NowPlayingPeeks(defaults: UserDefaults(suiteName: suite)!)
    }

    func track(_ title: String, app: String = "ru.yandex.desktop.music", parent: String? = nil) -> NowPlaying {
        NowPlaying(bundleId: app, parentBundleId: parent, title: title, artist: nil, album: nil, duration: 200, elapsed: 0,
                   timestamp: nil, isPlaying: true, rate: 1, artwork: nil, prohibitsSkip: false)
    }

    @Test func shortsAfterTheFirstGoQuiet() {
        let p = peeks()
        let chrome = "com.google.Chrome"
        #expect(p.allows(track("Длинное видео", app: chrome), now: t0))
        #expect(p.allows(track("Шортс 1", app: chrome), now: t0.addingTimeInterval(180)))
        #expect(!p.allows(track("Шортс 2", app: chrome), now: t0.addingTimeInterval(195)))
        #expect(!p.allows(track("Шортс 3", app: chrome), now: t0.addingTimeInterval(210)))
        // Stayed on one a while: the next is shown again.
        #expect(p.allows(track("Видео", app: chrome), now: t0.addingTimeInterval(300)))
    }

    @Test func skippingTracksAndResuming() {
        let p = peeks()
        #expect(p.allows(track("Первый"), now: t0))
        #expect(p.allows(track("Второй"), now: t0.addingTimeInterval(200)))   // played to its end
        #expect(!p.allows(track("Третий"), now: t0.addingTimeInterval(203)))  // «Следующий»
        // Play after a pause: the same track, not something new.
        #expect(p.allows(track("Третий"), now: t0.addingTimeInterval(210)))
    }

    @Test func silencedAppsAndTheSwitch() {
        let suite = "mely-peeks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let p = NowPlayingPeeks(defaults: defaults)
        p.setMuted("com.google.Chrome", true)
        #expect(!p.allows(track("Видео", app: "com.google.Chrome.helper", parent: "com.google.Chrome"), now: t0))
        #expect(p.allows(track("Песня"), now: t0.addingTimeInterval(100)))
        #expect(p.apps == ["ru.yandex.desktop.music", "com.google.Chrome"])
        p.isOn = false
        #expect(!p.allows(track("Другая"), now: t0.addingTimeInterval(300)))
        // Kept across launches.
        let again = NowPlayingPeeks(defaults: defaults)
        #expect(!again.isOn)
        #expect(again.isMuted("com.google.Chrome"))
        #expect(again.apps.first == "ru.yandex.desktop.music")
        again.setMuted("com.google.Chrome", false)
        #expect(!NowPlayingPeeks(defaults: defaults).isMuted("com.google.Chrome"))
    }
}
