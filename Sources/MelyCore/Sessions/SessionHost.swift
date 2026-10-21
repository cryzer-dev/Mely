// Portions © 2026 Louis Raillé, MIT License — see THIRD_PARTY_NOTICES.md.
import Foundation

/// The app a Claude Code session runs in.
public struct SessionHost: Equatable, Sendable {
    public enum Family: Equatable, Sendable { case terminal, vscode, jetbrains, unknown }

    /// Bundle id to bring forward, when known.
    public let bundleId: String?
    /// "WebStorm", "iTerm", "Терминал"…
    public let name: String
    public let family: Family

    public init(bundleId: String?, name: String, family: Family) {
        self.bundleId = bundleId
        self.name = name
        self.family = family
    }

    static let terminals: [String: String] = [
        "com.apple.Terminal": "Terminal",
        "com.googlecode.iterm2": "iTerm",
        "com.mitchellh.ghostty": "Ghostty",
        "dev.warp.Warp-Stable": "Warp",
        "dev.warp.Warp-Preview": "Warp",
        "net.kovidgoyal.kitty": "kitty",
        "com.github.wez.wezterm": "WezTerm",
        "org.alacritty": "Alacritty",
        "co.zeit.hyper": "Hyper",
        "dev.zed.Zed": "Zed",
        "com.cmuxterm.app": "cmux",
        // Claude desktop app: Code sessions on "Local" run on this Mac and fire the hooks.
        "com.anthropic.claudefordesktop": "Claude",
    ]
    static let termPrograms: [String: String] = [
        "apple_terminal": "com.apple.Terminal",
        "iterm.app": "com.googlecode.iterm2",
        "ghostty": "com.mitchellh.ghostty",
        "warpterminal": "dev.warp.Warp-Stable",
        "kitty": "net.kovidgoyal.kitty",
        "wezterm": "com.github.wez.wezterm",
        "alacritty": "org.alacritty",
        "hyper": "co.zeit.hyper",
        "zed": "dev.zed.Zed",
    ]
    static let editors: [String: String] = [
        "com.microsoft.VSCode": "VS Code",
        "com.microsoft.VSCodeInsiders": "VS Code Insiders",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.vscodium": "VSCodium",
    ]
    /// JetBrains IDEs by bundle id; EAP builds add "-EAP" (Toolbox installs keep the same ids).
    static let jetbrains: [String: String] = [
        "com.jetbrains.WebStorm": "WebStorm",
        "com.jetbrains.intellij": "IntelliJ IDEA",
        "com.jetbrains.intellij.ce": "IntelliJ IDEA CE",
        "com.jetbrains.pycharm": "PyCharm",
        "com.jetbrains.pycharm.ce": "PyCharm CE",
        "com.jetbrains.goland": "GoLand",
        "com.jetbrains.PhpStorm": "PhpStorm",
        "com.jetbrains.rubymine": "RubyMine",
        "com.jetbrains.rider": "Rider",
        "com.jetbrains.CLion": "CLion",
        "com.jetbrains.datagrip": "DataGrip",
        "com.jetbrains.rustrover": "RustRover",
        "com.jetbrains.fleet": "Fleet",
        "com.google.android.studio": "Android Studio",
    ]

    static let claudeDesktop = "com.anthropic.claudefordesktop"

    /// Known app for a bundle id, or nil.
    static func known(_ bundleId: String) -> SessionHost? {
        guard !bundleId.isEmpty else { return nil }
        if let name = terminals[bundleId] { return SessionHost(bundleId: bundleId, name: name, family: .terminal) }
        if let name = editors[bundleId] { return SessionHost(bundleId: bundleId, name: name, family: .vscode) }
        let base = bundleId.hasSuffix("-EAP") ? String(bundleId.dropLast(4)) : bundleId
        if let name = jetbrains[base] { return SessionHost(bundleId: bundleId, name: name, family: .jetbrains) }
        if base.hasPrefix("com.jetbrains.") { return SessionHost(bundleId: bundleId, name: "JetBrains IDE", family: .jetbrains) }
        return nil
    }

    /// Where a session runs. Never nil: an unrecognized host is shown as "Терминал"
    /// (before, such events were dropped and WebStorm sessions never showed up).
    public static func resolve(_ origin: HookOrigin) -> SessionHost {
        // Claude Code says it runs in the Claude app's Code tab.
        if origin.entrypoint == "claude-desktop", let host = known(claudeDesktop) { return host }
        // The process tree is the most reliable: it is the app that actually started `claude`.
        if let host = known(origin.hostBundleId) { return host }
        if let host = known(origin.bundleId) { return host }
        if origin.terminalEmulator.hasPrefix("JetBrains") {
            let id = [origin.hostBundleId, origin.bundleId].first { !$0.isEmpty }
            return SessionHost(bundleId: id, name: "JetBrains IDE", family: .jetbrains)
        }
        let program = origin.termProgram.lowercased()
        if program.contains("vscode") {
            return SessionHost(bundleId: "com.microsoft.VSCode", name: "VS Code", family: .vscode)
        }
        if let id = termPrograms[program], let host = known(id) { return host }
        let id = [origin.hostBundleId, origin.bundleId].first { !$0.isEmpty }
        return SessionHost(bundleId: id, name: "Терминал", family: .unknown)
    }
}
