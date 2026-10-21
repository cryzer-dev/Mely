import AppKit
import MelyCore

/// Mely and Mely Dev (`build-app.sh --dev`) share the hook socket, the relay and the
/// notch, so only one runs. Mely Dev takes over from Mely and gives it back on quit;
/// Mely does not start while Mely Dev runs.
@MainActor
enum DevBuildSwap {
    private static var replacedRelease: URL?

    /// Call first at launch. False: this Mely should quit at once.
    static func takeOver() -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        func running(_ id: String) -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != me }
        }
        guard AppInfo.isDevBuild else { return running(AppInfo.devBundleId).isEmpty }
        let release = running(AppInfo.bundleId)
        guard !release.isEmpty else { return true }
        replacedRelease = release.first?.bundleURL
        release.forEach { $0.terminate() }
        // Wait for it to close the socket before ours opens.
        let deadline = Date().addingTimeInterval(5)
        while release.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        release.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        return true
    }

    /// Call on quit: Mely Dev starts the Mely it replaced again.
    static func handBack() {
        guard AppInfo.isDevBuild, let url = replacedRelease else { return }
        // The release refuses to start while this process still runs: launch it after exit.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$0\"",
                          url.path]
        try? task.run()
    }
}
