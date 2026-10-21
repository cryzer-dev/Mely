import Testing
import Foundation
@testable import MelyCore

private func json(_ s: String?) -> [String: Any] {
    guard let s, let d = s.data(using: .utf8) else { return [:] }
    return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
}

@Suite struct HookDecisionTests {
    @Test func linesRoundTrip() {
        let cases: [HookDecision] = [.allow, .always, .deny, .ask,
                                     .answer(["Какой?": .single("A"), "Что ещё?": .multiple(["x", "y"])])]
        for d in cases { #expect(HookDecision(line: d.line) == d) }
        #expect(HookDecision(line: "garbage") == .ask)
        #expect(HookDecision(line: #"{"permissionDecision":"maybe"}"#) == .ask)
    }

    @Test func allowAndDenyForPermissionRequest() {
        let allow = json(HookDecision.allow.hookOutput(event: "PermissionRequest", payload: [:]))
        let hso = allow["hookSpecificOutput"] as? [String: Any]
        #expect(hso?["hookEventName"] as? String == "PermissionRequest")
        #expect((hso?["decision"] as? [String: Any])?["behavior"] as? String == "allow")

        let deny = json(HookDecision.deny.hookOutput(event: "PermissionRequest", payload: [:]))
        let denyDecision = (deny["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        #expect(denyDecision?["behavior"] as? String == "deny")
    }

    @Test func alwaysPassesSuggestions() {
        let payload: [String: Any] = ["permission_suggestions": [["type": "addRules"]]]
        let out = json(HookDecision.always.hookOutput(event: "PermissionRequest", payload: payload))
        let decision = (out["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        #expect((decision?["updatedPermissions"] as? [[String: Any]])?.count == 1)
    }

    @Test func askPrintsNothing() {
        #expect(HookDecision.ask.hookOutput(event: "PermissionRequest", payload: [:]) == nil)
        #expect(HookDecision.allow.hookOutput(event: "PreToolUse", payload: [:]) == nil)
    }

    @Test func answerForAskHookUsesPreToolUse() {
        let payload: [String: Any] = ["tool_input": ["questions": [["question": "Какой?"]]]]
        let out = json(HookDecision.answer(["Какой?": .multiple(["A", "B"])]).hookOutput(event: "PreToolUse", payload: payload))
        let hso = out["hookSpecificOutput"] as? [String: Any]
        #expect(hso?["hookEventName"] as? String == "PreToolUse")
        #expect(hso?["permissionDecision"] as? String == "allow")
        let updated = hso?["updatedInput"] as? [String: Any]
        #expect((updated?["answers"] as? [String: Any])?["Какой?"] as? [String] == ["A", "B"])
        #expect((updated?["questions"] as? [[String: Any]])?.count == 1)
    }
}

@Suite struct HookContextTests {
    @Test func enrichAddsJetBrainsContext() {
        var payload: [String: Any] = ["hook_event_name": "PreToolUse", "cwd": ""]
        HookContext.enrich(&payload,
                           env: ["TERMINAL_EMULATOR": "JetBrains-JediTerm", "__CFBundleIdentifier": "com.jetbrains.WebStorm"],
                           hostApp: "com.jetbrains.WebStorm", cwd: "/Users/me/shop")
        #expect(payload["terminal_emulator"] as? String == "JetBrains-JediTerm")
        #expect(payload["host_bundle_id"] as? String == "com.jetbrains.WebStorm")
        #expect(payload["cwd"] as? String == "/Users/me/shop")
        #expect(payload["term_program"] == nil)
    }

    @Test func enrichKeepsExistingValues() {
        var payload: [String: Any] = ["cwd": "/a", "term_program": "iTerm.app"]
        HookContext.enrich(&payload, env: ["TERM_PROGRAM": "vscode"], hostApp: nil, cwd: "/b")
        #expect(payload["cwd"] as? String == "/a")
        #expect(payload["term_program"] as? String == "iTerm.app")
    }

    @Test func outermostAppBundle() {
        #expect(HookContext.appBundlePath(containing: "/Applications/WebStorm.app/Contents/jbr/Contents/Home/bin/java")
                == "/Applications/WebStorm.app")
        #expect(HookContext.appBundlePath(containing:
            "/Users/me/Applications/WebStorm.app/Contents/plugins/x.app/Contents/MacOS/x") == "/Users/me/Applications/WebStorm.app")
        #expect(HookContext.appBundlePath(containing: "/bin/zsh") == nil)
    }
}
