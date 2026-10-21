import Foundation

/// Stable identifiers and locations. Changing any of these breaks Keychain items,
/// preferences, TCC grants or the hook socket path for existing installs.
public enum AppInfo {
    public static let bundleId = "dev.mely.app"
    /// Local builds (`build-app.sh --dev`): installed next to the release, never at once.
    public static let devBundleId = "dev.mely.app.dev"
    public static let name = "Mely"
    public static var isDevBuild: Bool { Bundle.main.bundleIdentifier == devBundleId }
    /// "0.1.0" from Info.plist; empty outside the app bundle.
    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// `~/.mely` — no spaces, so paths inside paste cleanly into a terminal.
    public static var dataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mely", isDirectory: true)
    }

    /// The hook socket. `MELY_SOCKET_PATH` overrides it (tests run a private server).
    public static var socketURL: URL {
        if let override = ProcessInfo.processInfo.environment["MELY_SOCKET_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return dataDirectory.appendingPathComponent("mely.sock")
    }
    public static var shelfDirectory: URL { dataDirectory.appendingPathComponent("shelf", isDirectory: true) }
}
