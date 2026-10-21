import AppKit
import Observation
import OSLog
import MelyCore
import MelyUI

private let log = Logger(subsystem: "dev.mely.app", category: "now-playing")

/// What plays on the Mac (Yandex Music, YouTube in a browser, Apple Music…) through the
/// system Now Playing. Since macOS 15.4 only Apple's processes may read it, so
/// mediaremote-adapter runs inside `/usr/bin/perl` and streams JSON (task 5.1).
@MainActor
@Observable
final class NowPlayingIntegration: Integration {
    let id = "now-playing"
    let displayName = "Что играет"
    let summary = "Мини-плеер: Яндекс Музыка, YouTube в браузере и другие плееры"
    private(set) var status: IntegrationStatus = .off
    let model = NowPlayingModel()

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var running = false
    /// A new track: a short preview with the cover.
    @ObservationIgnored var peek: ((PeekContent) -> Void)?
    /// The preview waits for the player to finish switching tracks.
    @ObservationIgnored private var peekTask: Task<Void, Never>?

    /// The adapter bundled by build-app.sh, in Contents/Resources/MediaRemote.
    private static var adapter: (script: URL, framework: URL)? {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("MediaRemote") else { return nil }
        let script = dir.appendingPathComponent("mediaremote-adapter.pl")
        let framework = dir.appendingPathComponent("MediaRemoteAdapter.framework")
        let fm = FileManager.default
        return fm.fileExists(atPath: script.path) && fm.fileExists(atPath: framework.path) ? (script, framework) : nil
    }

    func start() async {
        // A previous Mely killed without cleanup leaves its adapter streaming: end it.
        let cleanup = Process()
        cleanup.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        cleanup.arguments = ["-f", "Contents/Resources/MediaRemote/mediaremote-adapter.pl"]
        try? cleanup.run()
        cleanup.waitUntilExit()
        guard Self.adapter != nil else {
            status = .error("Нет адаптера Now Playing: соберите приложение через scripts/build-app.sh")
            return
        }
        running = true
        status = .running
        launch()
    }

    func stop() async {
        running = false
        readTask?.cancel()
        process?.terminate()
        process = nil
        model.update(nil)
        status = .off
    }

    /// `stream` until it dies; then again a little later (the adapter can exit when the
    /// media daemon restarts).
    private func launch() {
        guard running, let adapter = Self.adapter else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [adapter.script.path, adapter.framework.path, "stream", "--debounce=150"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            status = .error("Не удалось запустить адаптер Now Playing")
            return
        }
        self.process = process
        log.info("adapter started")
        readTask = Task.detached { [weak self] in
            var stream = NowPlayingStream()
            // Not `bytes.lines`: its readers take turns, and this one waits for hours.
            for await line in PipeLines.lines(out.fileHandleForReading) {
                guard let state = stream.apply(line: line) else { continue }
                await self?.receive(state)
            }
            await self?.relaunchLater()
        }
    }

    private func relaunchLater() {
        guard running else { return }
        log.info("adapter stopped, restarting")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.launch()
        }
    }

    private func receive(_ state: NowPlaying?) {
        log.debug("state \(state?.sourceBundleId ?? "-", privacy: .public) playing=\(state?.isPlaying ?? false, privacy: .public)")
        guard model.update(state) else { return }
        // A player switching tracks says "playing" with the old track first and the new
        // title and cover a moment later: show whatever plays once it has settled.
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, let np = self.model.current, np.isPlaying else { return }
            log.info("playing from \(np.sourceBundleId, privacy: .public)")
            self.peek?(PeekContent(id: "now-playing", symbol: "music.note", tint: .blue, title: np.title,
                                   subtitle: np.artist ?? NowPlayingIntegration.appName(np.sourceBundleId),
                                   appBundleId: np.sourceBundleId, artwork: np.artwork))
        }
    }

    /// Play/pause, next, previous: one short `send` call.
    func send(_ command: MediaCommand) {
        guard let adapter = Self.adapter else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [adapter.script.path, adapter.framework.path, "send", String(command.rawValue)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    func openSource(_ bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }

    static func appName(_ bundleId: String) -> String { MiniPlayerView.appName(bundleId) }
}
