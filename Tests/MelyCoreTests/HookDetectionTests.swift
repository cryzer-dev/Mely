// Portions © 2026 Louis Raillé, MIT License — see THIRD_PARTY_NOTICES.md.
import Testing
import Foundation
@testable import MelyCore

@Suite struct HookDetectionTests {
    func settings(_ json: String) -> [String: Any] {
        ((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]) ?? [:]
    }

    @Test func melyHookDetected() {
        #expect(HookDetection.melyHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"\\"/Users/me/.mely/bin/nc-hook\\""}]}]}}
        """)))
        // Alongside somebody else's hook.
        #expect(HookDetection.melyHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[
          {"hooks":[{"type":"command","command":"/usr/local/bin/other-tool"}]},
          {"hooks":[{"type":"command","command":"/Users/me/.mely/bin/nc-hook"}]}]}}
        """)))
    }

    @Test func otherToolsAreNotMely() {
        #expect(!HookDetection.melyHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[{"hooks":[
          {"type":"command","command":"$HOME/.vibe-island/bin/vibe-island-bridge"},
          {"type":"command","command":"python3 /Users/me/.claude/skills/harness/hook.py"}]}]}}
        """)))
        // Hooks for other events do not count.
        #expect(!HookDetection.melyHooksPresent(inSettings: settings("""
        {"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"/Users/me/.mely/bin/nc-hook"}]}]}}
        """)))
    }

    @Test(arguments: ["{}", #"{"hooks":{"SessionStart":[]}}"#, #"{"hooks":{"SessionStart":[{"hooks":[{"type":"command"}]}]}}"#,
                      #"{"hooks":{"SessionStart":"not-an-array"}}"#, #"{"hooks":"not-an-object"}"#])
    func malformedNeverReadsAsInstalled(json: String) {
        #expect(!HookDetection.melyHooksPresent(inSettings: settings(json)))
    }
}
