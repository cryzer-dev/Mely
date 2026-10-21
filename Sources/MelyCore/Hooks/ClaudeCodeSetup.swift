import Foundation

/// A change to ~/.claude/settings.json waiting for the user's OK.
public struct PendingSettingsChange: Sendable {
    public let title: String
    /// Changed lines with a little context, `+`/`-` prefixed.
    public let diff: String
    public let newData: Data
    /// The bytes the diff was computed from; the write is refused if the file changed since.
    public let originalBytes: Data?
    /// The statusLine Mely's wrapper calls, written next to the relay with the settings.
    public let previousStatusLine: ClaudeHookInstaller.PreviousStatusLine
    public var isEmpty: Bool { diff.isEmpty }

    public init(title: String, diff: String, newData: Data, originalBytes: Data?,
                previousStatusLine: ClaudeHookInstaller.PreviousStatusLine = .keep) {
        self.title = title
        self.diff = diff
        self.newData = newData
        self.originalBytes = originalBytes
        self.previousStatusLine = previousStatusLine
    }
}

/// File side of connecting Claude Code: the relay binary at a stable path without spaces,
/// and the settings change built by `ClaudeHookInstaller`.
public struct ClaudeCodeSetup: Sendable {
    public let settingsURL: URL
    public let relayURL: URL
    /// The user's statusLine before Mely; `nc-hook --statusline` runs it.
    public let previousStatusLineURL: URL

    public init(settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"),
                relayURL: URL = AppInfo.dataDirectory.appendingPathComponent("bin/nc-hook"),
                previousStatusLineURL: URL? = nil) {
        self.settingsURL = settingsURL
        self.relayURL = relayURL
        // Next to bin/: ~/.mely/statusline-previous.json, where `nc-hook --statusline` looks.
        self.previousStatusLineURL = previousStatusLineURL ?? relayURL.deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("statusline-previous.json")
    }

    /// Copies the relay shipped in the app bundle to `relayURL` (0755), replacing an older one.
    public func installRelay(from bundled: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: relayURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        if let a = try? Data(contentsOf: bundled), let b = try? Data(contentsOf: relayURL), a == b { return }
        let temp = relayURL.appendingPathExtension("new")
        try? fm.removeItem(at: temp)
        try fm.copyItem(at: bundled, to: temp)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.path)
        _ = try fm.replaceItemAt(relayURL, withItemAt: temp)
    }

    /// Hooks and the statusLine wrapper (plan limits) are both in place.
    public func hooksInstalled() -> Bool {
        guard let snapshot = try? ClaudeSettingsFile.read(at: settingsURL) else { return false }
        return HookDetection.melyHooksPresent(inSettings: snapshot.object, relayPath: relayURL.path)
            && ClaudeHookInstaller.statusLineInstalled(in: snapshot.object, relayPath: relayURL.path)
    }

    /// Mely's hooks are there, but not the statusLine wrapper (installed before plan limits).
    public func onlyStatusLineMissing() -> Bool {
        guard let snapshot = try? ClaudeSettingsFile.read(at: settingsURL) else { return false }
        return HookDetection.melyHooksPresent(inSettings: snapshot.object, relayPath: relayURL.path)
            && !ClaudeHookInstaller.statusLineInstalled(in: snapshot.object, relayPath: relayURL.path)
    }

    public func prepareInstall() throws -> PendingSettingsChange {
        var previous = ClaudeHookInstaller.PreviousStatusLine.keep
        return try prepare(title: "Подключить Claude Code", previous: { previous }) { [relayURL] settings in
            let hooked = try ClaudeHookInstaller.installing(into: settings, relayPath: relayURL.path)
            let result = ClaudeHookInstaller.installingStatusLine(into: hooked, relayPath: relayURL.path)
            previous = result.previous
            return result.settings
        }
    }

    public func prepareUninstall() throws -> PendingSettingsChange {
        try prepare(title: "Отключить hooks Mely", previous: { .save(nil) }) { [relayURL] settings in
            let unhooked = try ClaudeHookInstaller.uninstalling(from: settings, relayPath: relayURL.path)
            return ClaudeHookInstaller.uninstallingStatusLine(from: unhooked, relayPath: relayURL.path,
                                                              previous: Self.readJSON(previousStatusLineURL))
        }
    }

    /// Writes after a dated backup; refused if settings.json changed since the preview.
    /// The saved previous statusLine follows only once settings.json is written.
    @discardableResult
    public func apply(_ change: PendingSettingsChange) throws -> URL? {
        let backup = try ClaudeSettingsFile.write(change.newData, to: settingsURL, expecting: change.originalBytes)
        if case .save(let data) = change.previousStatusLine {
            if let data {
                try FileManager.default.createDirectory(at: previousStatusLineURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try data.write(to: previousStatusLineURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: previousStatusLineURL)
            }
        }
        return backup
    }

    private func prepare(title: String, previous: () -> ClaudeHookInstaller.PreviousStatusLine = { .keep },
                         _ transform: ([String: Any]) throws -> [String: Any]) throws -> PendingSettingsChange {
        let snapshot = try ClaudeSettingsFile.read(at: settingsURL)
        let newData = try ClaudeHookInstaller.encode(try transform(snapshot.object))
        // Diff against the same pretty form, so key order or spacing never shows as a change.
        let before = snapshot.bytes == nil ? "" : String(decoding: try ClaudeHookInstaller.encode(snapshot.object), as: UTF8.self)
        let diff = LineDiff.text(from: before, to: String(decoding: newData, as: UTF8.self))
        return PendingSettingsChange(title: title, diff: diff, newData: newData, originalBytes: snapshot.bytes,
                                     previousStatusLine: previous())
    }

    private static func readJSON(_ url: URL) -> [String: Any]? {
        (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}
