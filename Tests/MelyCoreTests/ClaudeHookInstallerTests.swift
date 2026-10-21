import Testing
import Foundation
@testable import MelyCore

@Suite struct ClaudeHookInstallerTests {
    let relay = "/Users/me/.mely/bin/nc-hook"

    func settings(_ json: String) -> [String: Any] {
        ((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]) ?? [:]
    }

    func commands(_ s: [String: Any], _ event: String) -> [String] {
        ((s["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? [])
            .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
    }

    let fixture = """
    {"model":"opus","env":{"FOO":"1"},
     "hooks":{
       "PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/guard"}]}],
       "Stop":[{"hooks":[{"type":"command","command":"say done"}]}],
       "SessionStart":[{"hooks":[{"type":"command","command":"/usr/local/bin/session-log"}]}]
     }}
    """

    @Test func mergesWithoutTouchingOtherHooks() throws {
        let out = try ClaudeHookInstaller.installing(into: settings(fixture), relayPath: relay)
        #expect(out["model"] as? String == "opus")
        #expect((out["env"] as? [String: Any])?["FOO"] as? String == "1")
        #expect(commands(out, "PreToolUse").contains("/usr/local/bin/guard"))
        #expect(commands(out, "Stop") == ["say done", "\"\(relay)\""])
        #expect(commands(out, "PreToolUse").contains("\"\(relay)\" --ask"))
        // Another tool's hook stays.
        #expect(commands(out, "SessionStart").count == 2)
        #expect(HookDetection.melyHooksPresent(inSettings: out))
    }

    @Test func permissionTimeoutCoversTheWait() throws {
        let out = try ClaudeHookInstaller.installing(into: [:], relayPath: relay)
        let group = ((out["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])?.first
        let timeout = (group?["hooks"] as? [[String: Any]])?.first?["timeout"] as? Int
        #expect(timeout == 120)
    }

    @Test func reinstallDoesNotDuplicate() throws {
        let once = try ClaudeHookInstaller.installing(into: settings(fixture), relayPath: relay)
        let twice = try ClaudeHookInstaller.installing(into: once, relayPath: relay)
        #expect(commands(twice, "Stop") == ["say done", "\"\(relay)\""])
        #expect(commands(twice, "PreToolUse").filter { $0.contains("nc-hook") }.count == 2)
    }

    @Test func uninstallRemovesOnlyMely() throws {
        let installed = try ClaudeHookInstaller.installing(into: settings(fixture), relayPath: relay)
        let out = try ClaudeHookInstaller.uninstalling(from: installed)
        #expect(commands(out, "PreToolUse") == ["/usr/local/bin/guard"])
        #expect(commands(out, "Stop") == ["say done"])
        #expect((out["hooks"] as? [String: Any])?["PermissionRequest"] == nil)
        #expect(commands(out, "SessionStart") == ["/usr/local/bin/session-log"])
        #expect(!HookDetection.melyHooksPresent(inSettings: out))
    }

    @Test func unknownHooksShapeIsRefused() {
        #expect(throws: ClaudeSettingsFile.Failure.self) {
            try ClaudeHookInstaller.installing(into: settings(#"{"hooks":"off"}"#), relayPath: relay)
        }
    }

    @Test func diffShowsOnlyChanges() {
        let diff = LineDiff.text(from: "a\nb\nc\nd\ne\nf\ng", to: "a\nb\nc\nX\ne\nf\ng", context: 1)
        #expect(diff == "  c\n- d\n+ X\n  e")
        #expect(LineDiff.text(from: "same", to: "same").isEmpty)
        #expect(LineDiff.text(from: "", to: "{}") == "+ {}")
    }
}
