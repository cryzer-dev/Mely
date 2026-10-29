import Testing
import Foundation
@testable import MelyCore

@Suite struct CodexHookInstallerTests {
    let relay = "/Users/me/.mely/bin/nc-hook"
    let path = "/Users/me/.codex/hooks.json"

    func groups(_ file: [String: Any], _ event: String) -> [[String: Any]] {
        (file["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
    }

    @Test func installsIntoAnEmptyFile() throws {
        let file = try CodexHookInstaller.installing(into: [:], relayPath: relay)
        #expect(CodexHookInstaller.complete(file, relayPath: relay))
        let permission = try #require(groups(file, "PermissionRequest").first?["hooks"] as? [[String: Any]]).first
        #expect(permission?["command"] as? String == "\"\(relay)\" --agent codex")
        #expect(permission?["timeout"] as? Int == 120)
        #expect(permission?["statusMessage"] as? String == "Ждёт ответа в Mely")
        #expect(((groups(file, "Stop").first?["hooks"] as? [[String: Any]])?.first)?["statusMessage"] == nil)
    }

    @Test func keepsOtherHooksAndDoesNotDuplicate() throws {
        let theirs: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]]
        let once = try CodexHookInstaller.installing(into: theirs, relayPath: relay)
        let twice = try CodexHookInstaller.installing(into: once, relayPath: relay)
        #expect(groups(twice, "Stop").count == 2)
        #expect((groups(twice, "Stop")[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String == "say done")
        #expect(CodexHookInstaller.melySlots(in: twice, relayPath: relay).count == CodexHookInstaller.events.count)
        // Claude Code's relay without `--agent codex` is not Codex's.
        #expect(!CodexHookInstaller.isMelyCommand("\"\(relay)\"", relayPath: relay))
    }

    @Test func uninstallKeepsTheirs() throws {
        let theirs: [String: Any] = ["model": "gpt-5-codex",
                                     "hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]]
        let back = try CodexHookInstaller.uninstalling(from: CodexHookInstaller.installing(into: theirs, relayPath: relay),
                                                       relayPath: relay)
        #expect(groups(back, "Stop").count == 1)
        #expect(groups(back, "PermissionRequest").isEmpty)
        #expect(back["model"] as? String == "gpt-5-codex")
        #expect(try CodexHookInstaller.uninstalling(from: CodexHookInstaller.installing(into: [:], relayPath: relay),
                                                    relayPath: relay).isEmpty)
    }

    @Test func slotsMakeCodexKeys() throws {
        let theirs: [String: Any] = ["hooks": ["PermissionRequest": [["hooks": [["type": "command", "command": "audit"]]]]]]
        let file = try CodexHookInstaller.installing(into: theirs, relayPath: relay)
        let slot = try #require(CodexHookInstaller.melySlots(in: file, relayPath: relay).first { $0.event == "PermissionRequest" })
        // Their group comes first: Mely's is group 1.
        #expect(slot.key(hooksPath: path) == "\(path):permission_request:1:0")
        #expect(CodexHookInstaller.snakeCase("UserPromptSubmit") == "user_prompt_submit")
    }
}

@Suite struct CodexHookTrustTests {
    let path = "/Users/me/.codex/hooks.json"

    @Test func addsAndRemovesOnlyItsTables() {
        let theirs = """
        model = "gpt-5-codex"
        # мой комментарий

        [mcp_servers.github]
        command = "gh-mcp"

        """
        let key = "\(path):stop:0:0"
        let trusted = CodexHookTrust.trusting(theirs, hashes: [key: "sha256:abc"])
        #expect(trusted.hasPrefix(theirs))
        #expect(CodexHookTrust.trustedHashes(in: trusted) == [key: "sha256:abc"])
        // Again, with a new hash: one table, not two (a duplicate table breaks Codex's config).
        let again = CodexHookTrust.trusting(trusted, hashes: [key: "sha256:def"])
        #expect(again.components(separatedBy: "[hooks.state.").count == 2)
        #expect(CodexHookTrust.trustedHashes(in: again) == [key: "sha256:def"])
        // Off: the file is what it was.
        #expect(CodexHookTrust.untrusting(again) == theirs)
    }

    @Test func replacesATableCodexWroteForTheSameKey() {
        let key = "\(path):stop:0:0"
        let codexWrote = "[hooks.state.\"\(key)\"]\ntrusted_hash = \"sha256:old\"\nenabled = true\n\n[tui]\ntheme = \"dark\""
        let trusted = CodexHookTrust.trusting(codexWrote, hashes: [key: "sha256:new"])
        #expect(CodexHookTrust.trustedHashes(in: trusted) == [key: "sha256:new"])
        #expect(trusted.contains("[tui]\ntheme = \"dark\""))
        #expect(!trusted.contains("sha256:old"))
    }

    @Test func emptyConfig() {
        let key = "\(path):stop:0:0"
        let trusted = CodexHookTrust.trusting("", hashes: [key: "sha256:abc"])
        #expect(trusted.hasPrefix(CodexHookTrust.marker))
        #expect(CodexHookTrust.untrusting(trusted) == "")
    }

    @Test func hashesFromHooksListBySuffix() {
        let relay = "/Users/me/.mely/bin/nc-hook"
        let temp = "/tmp/x/hooks.json"
        let response: [String: Any] = ["data": [["cwd": "/tmp", "hooks": [
            ["key": "\(temp):permission_request:0:0", "sourcePath": temp, "command": "\"\(relay)\" --agent codex",
             "currentHash": "sha256:p", "trustStatus": "untrusted"],
            ["key": "\(temp):stop:0:0", "sourcePath": temp, "command": "say done", "currentHash": "sha256:s",
             "trustStatus": "trusted"],
        ]]]]
        #expect(CodexHookTrust.hashes(fromHooksList: response, relayPath: relay) == ["permission_request:0:0": "sha256:p"])
        #expect(CodexHookTrust.statuses(fromHooksList: response, relayPath: relay) == ["untrusted"])
    }
}
