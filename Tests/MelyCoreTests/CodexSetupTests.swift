import Testing
import Foundation
@testable import MelyCore

@Suite struct CodexSetupTests {
    func scratch() throws -> (CodexSetup, URL) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("mely-codex-setup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return (CodexSetup(codexHome: home, relayURL: URL(fileURLWithPath: "/Users/me/.mely/bin/nc-hook")), home)
    }

    /// A stand-in for Codex: one hash per slot suffix of the file it is shown.
    func fakeHashes(_ data: Data) throws -> [String: String] {
        let file = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Dictionary(uniqueKeysWithValues: CodexHookInstaller.melySlots(in: file, relayPath: "/Users/me/.mely/bin/nc-hook")
            .map { ($0.suffix, "sha256:\($0.suffix)") })
    }

    @Test func installThenUninstallLeavesTheirsAsItWas() async throws {
        let (setup, home) = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let theirConfig = "model = \"gpt-5-codex\"\n"
        try Data(theirConfig.utf8).write(to: setup.configURL)
        #expect(setup.state() == .notInstalled)

        let install = try await setup.prepareInstall(hashes: fakeHashes)
        #expect(install.diff.contains("~/.codex/hooks.json"))
        #expect(install.diff.contains("~/.codex/config.toml"))
        try setup.apply(install)
        #expect(setup.state() == .installed)
        let config = try String(contentsOf: setup.configURL, encoding: .utf8)
        #expect(config.hasPrefix(theirConfig))
        #expect(CodexHookTrust.trustedHashes(in: config).count == CodexHookInstaller.events.count)

        // Again: nothing doubles.
        try setup.apply(try await setup.prepareInstall(hashes: fakeHashes))
        #expect(CodexHookTrust.trustedHashes(in: try String(contentsOf: setup.configURL, encoding: .utf8)).count
                == CodexHookInstaller.events.count)

        try setup.apply(try setup.prepareUninstall())
        #expect(setup.state() == .notInstalled)
        #expect(try String(contentsOf: setup.configURL, encoding: .utf8) == theirConfig)
    }

    @Test func refusesWhenAFileChangedSinceThePreview() async throws {
        let (setup, home) = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let install = try await setup.prepareInstall(hashes: fakeHashes)
        try Data("model = \"o3\"\n".utf8).write(to: setup.configURL)
        #expect(throws: ClaudeSettingsFile.Failure.self) { try setup.apply(install) }
        // Nothing was written: hooks.json is not there either.
        #expect(!FileManager.default.fileExists(atPath: setup.hooksURL.path))
    }

    @Test func approvalRemovedByHandIsChanged() async throws {
        let (setup, home) = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        try setup.apply(try await setup.prepareInstall(hashes: fakeHashes))
        try Data().write(to: setup.configURL)
        #expect(setup.state() == .changed)
    }

    /// With the real Codex (when installed): after «Применить» Codex counts Mely's hooks trusted.
    @Test(.enabled(if: CodexAppServer.locate() != nil)) func codexTrustsTheHooks() async throws {
        let (setup, home) = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let codex = try #require(CodexAppServer.locate())
        let install = try await setup.prepareInstall { try await setup.hashes(for: $0, codex: codex) }
        try setup.apply(install)
        let statuses = try await setup.trustStatuses(codex: codex)
        #expect(statuses.count == CodexHookInstaller.events.count)
        #expect(Set(statuses) == ["trusted"])
    }
}
