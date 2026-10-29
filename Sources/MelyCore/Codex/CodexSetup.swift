import Foundation

/// File side of connecting Codex: Mely's hooks in `~/.codex/hooks.json` and Codex's
/// approval of them in `~/.codex/config.toml`, both shown in one diff, written together.
public struct CodexSetup: Sendable {
    public enum State: Equatable, Sendable {
        case notInstalled
        case installed
        /// Some of Mely's hooks or their approvals are gone: installing again fixes it.
        case changed
    }

    public let hooksURL: URL
    public let configURL: URL
    public let relayURL: URL

    public init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
                relayURL: URL = AppInfo.dataDirectory.appendingPathComponent("bin/nc-hook")) {
        hooksURL = codexHome.appendingPathComponent("hooks.json")
        configURL = codexHome.appendingPathComponent("config.toml")
        self.relayURL = relayURL
    }

    /// From the files alone; whether Codex accepts the hashes is `trustStatuses`.
    public func state() -> State {
        guard let hooks = try? ClaudeSettingsFile.read(at: hooksURL).object else { return .changed }
        let slots = CodexHookInstaller.melySlots(in: hooks, relayPath: relayURL.path)
        guard !slots.isEmpty else { return .notInstalled }
        let trusted = CodexHookTrust.trustedHashes(in: readConfig().text)
        let allTrusted = slots.allSatisfy { trusted[$0.key(hooksPath: keyPath)] != nil }
        return CodexHookInstaller.complete(hooks, relayPath: relayURL.path) && allTrusted ? .installed : .changed
    }

    /// The hooks and their approvals. `hashes` gets Codex's hash of each Mely hook from a
    /// copy of the new hooks.json (by slot suffix); see `hashes(for:codex:)`.
    public func prepareInstall(hashes: @Sendable (Data) async throws -> [String: String]) async throws -> PendingSettingsChange {
        let snapshot = try ClaudeSettingsFile.read(at: hooksURL)
        let file = try CodexHookInstaller.installing(into: snapshot.object, relayPath: relayURL.path)
        let newHooks = try ClaudeHookInstaller.encode(file)
        let bySuffix = try await hashes(newHooks)
        let slots = CodexHookInstaller.melySlots(in: file, relayPath: relayURL.path)
        var trust: [String: String] = [:]
        for slot in slots {
            guard let hash = bySuffix[slot.suffix] else { throw CodexAppServer.Failure.rpc("Codex не вернул хеш для \(slot.event)") }
            trust[slot.key(hooksPath: keyPath)] = hash
        }
        // Approvals of hooks Mely had before (other slots) go with the old tables.
        let config = readConfig()
        let oldKeys = Set(CodexHookInstaller.melySlots(in: snapshot.object, relayPath: relayURL.path).map { $0.key(hooksPath: keyPath) })
        let newConfig = CodexHookTrust.trusting(CodexHookTrust.untrusting(config.text, keys: oldKeys), hashes: trust)
        return change(title: "Подключить Codex", snapshot: snapshot, newHooks: newHooks, config: config, newConfig: newConfig)
    }

    public func prepareUninstall() throws -> PendingSettingsChange {
        let snapshot = try ClaudeSettingsFile.read(at: hooksURL)
        let file = try CodexHookInstaller.uninstalling(from: snapshot.object, relayPath: relayURL.path)
        let keys = Set(CodexHookInstaller.melySlots(in: snapshot.object, relayPath: relayURL.path).map { $0.key(hooksPath: keyPath) })
        let config = readConfig()
        return change(title: "Отключить hooks Mely в Codex", snapshot: snapshot, newHooks: try ClaudeHookInstaller.encode(file),
                      config: config, newConfig: CodexHookTrust.untrusting(config.text, keys: keys))
    }

    /// Writes both files after dated backups; refused if either changed since the preview
    /// (checked before anything is written).
    public func apply(_ change: PendingSettingsChange) throws {
        for file in change.also {
            let current = try? Data(contentsOf: file.url)
            if current != file.originalBytes { throw ClaudeSettingsFile.Failure.changed(file.url.lastPathComponent) }
        }
        _ = try ClaudeSettingsFile.write(change.newData, to: hooksURL, expecting: change.originalBytes)
        for file in change.also {
            _ = try ClaudeSettingsFile.write(file.newData, to: file.url, expecting: file.originalBytes)
        }
    }

    /// Codex's own hashes of the hooks in `hooksData`, by slot suffix: the file goes into a
    /// scratch `CODEX_HOME` and Codex lists it (the hash does not depend on the path).
    public func hashes(for hooksData: Data, codex: URL) async throws -> [String: String] {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("mely-codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try hooksData.write(to: home.appendingPathComponent("hooks.json"))
        let list = try await CodexAppServer.request("hooks/list", params: ["cwds": [home.path]], codex: codex,
                                                    codexHome: home, cwd: home)
        return CodexHookTrust.hashes(fromHooksList: list, relayPath: relayURL.path)
    }

    /// What Codex says of Mely's installed hooks: `trusted`, `untrusted`, `modified`.
    public func trustStatuses(codex: URL) async throws -> [String] {
        let home = hooksURL.deletingLastPathComponent()
        let list = try await CodexAppServer.request("hooks/list", params: ["cwds": [home.path]], codex: codex,
                                                    codexHome: home, cwd: home)
        return CodexHookTrust.statuses(fromHooksList: list, relayPath: relayURL.path)
    }

    /// hooks.json's path as Codex keys approvals by: through symlinks (`/var` is
    /// `/private/var`; `~/.codex` may live in a dotfiles repo).
    var keyPath: String {
        let dir = hooksURL.deletingLastPathComponent().path
        guard let real = realpath(dir, nil) else { return hooksURL.path }
        defer { free(real) }
        return String(cString: real) + "/" + hooksURL.lastPathComponent
    }

    private func readConfig() -> (text: String, bytes: Data?) {
        let bytes = try? Data(contentsOf: configURL)
        return (bytes.map { String(decoding: $0, as: UTF8.self) } ?? "", bytes)
    }

    private func change(title: String, snapshot: (object: [String: Any], bytes: Data?), newHooks: Data,
                        config: (text: String, bytes: Data?), newConfig: String) -> PendingSettingsChange {
        let before = snapshot.bytes == nil ? "" : ((try? ClaudeHookInstaller.encode(snapshot.object)).map { String(decoding: $0, as: UTF8.self) } ?? "")
        var parts: [String] = []
        let hooksDiff = LineDiff.text(from: before, to: String(decoding: newHooks, as: UTF8.self))
        if !hooksDiff.isEmpty { parts.append("~/.codex/hooks.json\n" + hooksDiff) }
        let configDiff = LineDiff.text(from: config.text, to: newConfig)
        if !configDiff.isEmpty { parts.append("~/.codex/config.toml\n" + configDiff) }
        var change = PendingSettingsChange(title: title, diff: parts.joined(separator: "\n\n"), newData: newHooks,
                                           originalBytes: snapshot.bytes)
        change.note = "Mely изменит ~/.codex/hooks.json и одобрит свои hooks в ~/.codex/config.toml: без одобрения Codex их не запускает. Перед записью будут резервные копии, чужие hooks и настройки останутся на месте."
        if newConfig != config.text {
            change.also = [PendingFileWrite(url: configURL, newData: Data(newConfig.utf8), originalBytes: config.bytes)]
        }
        return change
    }
}
