import Testing
import Foundation
@testable import MelyCore

@Suite struct ClaudeCodeSetupTests {
    func temp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mely-setup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func installUninstallRoundTripWithBackup() throws {
        let dir = try temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = dir.appendingPathComponent("settings.json")
        let original = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        try Data(original.utf8).write(to: settings)
        let setup = ClaudeCodeSetup(settingsURL: settings, relayURL: dir.appendingPathComponent("bin/nc-hook"))

        let install = try setup.prepareInstall()
        #expect(install.diff.contains("+ "))
        #expect(!setup.hooksInstalled())
        let backup = try setup.apply(install)
        #expect(backup.map { (try? Data(contentsOf: $0)) == Data(original.utf8) } == true)
        #expect(setup.hooksInstalled())

        let uninstall = try setup.prepareUninstall()
        try setup.apply(uninstall)
        #expect(!setup.hooksInstalled())
        let after = try ClaudeSettingsFile.read(at: settings).object
        #expect(after["model"] as? String == "opus")
    }

    @Test func refusesWhenFileChangedAfterPreview() throws {
        let dir = try temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = dir.appendingPathComponent("settings.json")
        try Data("{}".utf8).write(to: settings)
        let setup = ClaudeCodeSetup(settingsURL: settings, relayURL: dir.appendingPathComponent("bin/nc-hook"))
        let change = try setup.prepareInstall()
        try Data(#"{"model":"edited"}"#.utf8).write(to: settings)
        #expect(throws: ClaudeSettingsFile.Failure.changed("settings.json")) { try setup.apply(change) }
    }

    @Test func noSettingsFileYet() throws {
        let dir = try temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let setup = ClaudeCodeSetup(settingsURL: dir.appendingPathComponent("missing/settings.json"),
                                    relayURL: dir.appendingPathComponent("bin/nc-hook"))
        let change = try setup.prepareInstall()
        try setup.apply(change)
        #expect(setup.hooksInstalled())
    }

    @Test func relayCopiedExecutable() throws {
        let dir = try temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bundled = dir.appendingPathComponent("nc-hook-src")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: bundled)
        let setup = ClaudeCodeSetup(settingsURL: dir.appendingPathComponent("s.json"), relayURL: dir.appendingPathComponent("bin/nc-hook"))
        try setup.installRelay(from: bundled)
        try setup.installRelay(from: bundled)
        #expect(FileManager.default.isExecutableFile(atPath: setup.relayURL.path))
    }
}
