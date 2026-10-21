import AppKit
import AVFoundation
import MelyCore

/// Mely's sounds (task 7.4): its own set in Contents/Resources/Sounds (made by
/// scripts/make-sounds.py), each replaceable by a file of the same name in ~/.mely/sounds
/// (.wav, .m4a, .mp3, .aiff). Silent when switched off, and during a Focus.
@MainActor
final class SoundEngine {
    enum Sound: String, CaseIterable {
        case greet, finish, approval, question, error, limit, drop, pop, poke, home, open, close, send
    }

    static let shared = SoundEngine()
    var behavior: IslandBehavior?

    private var players: [Sound: AVAudioPlayer] = [:]
    private var lastPlayed: [Sound: Date] = [:]

    static var customFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mely/sounds", isDirectory: true)
    }

    private init() { reload() }

    /// Re-reads the files: the user's replacements win over the built-in ones.
    func reload() {
        players = [:]
        for sound in Sound.allCases {
            guard let url = Self.customURL(sound) ?? Bundle.main.url(forResource: sound.rawValue, withExtension: "wav",
                                                                     subdirectory: "Sounds"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[sound] = player
        }
    }

    /// How many sounds the user replaced.
    var customized: Int { Sound.allCases.filter { Self.customURL($0) != nil }.count }

    static func customURL(_ sound: Sound) -> URL? {
        for ext in ["wav", "m4a", "mp3", "aiff", "caf"] {
            let url = customFolder.appendingPathComponent("\(sound.rawValue).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    func revealCustomFolder() {
        try? FileManager.default.createDirectory(at: Self.customFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([Self.customFolder])
    }

    /// Set by the app: quiet over a full-screen app (`FullScreenMode`).
    var isQuiet: (Sound) -> Bool = { _ in false }

    /// Plays unless sounds are off, a Focus is on or a full-screen app wants quiet; the same
    /// sound at most every 0.25 s.
    func play(_ sound: Sound, force: Bool = false) {
        let behavior = behavior
        guard force || behavior?.soundOn ?? true, force || !SystemFocus.isOn(), force || !isQuiet(sound),
              let player = players[sound] else { return }
        let now = Date()
        if let last = lastPlayed[sound], now.timeIntervalSince(last) < 0.25 { return }
        lastPlayed[sound] = now
        player.volume = Float(behavior?.soundVolume ?? 0.5)
        player.currentTime = 0
        player.play()
    }
}
