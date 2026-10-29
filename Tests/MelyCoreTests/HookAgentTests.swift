import Testing
import Foundation
@testable import MelyCore

/// A Codex hook payload saved from the 0.165 schema (`Fixtures/`), as `nc-hook --agent codex` relays it.
func codexPayload(_ name: String) throws -> [String: Any] {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    var payload = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    payload[HookWire.agentKey] = "codex"
    return payload
}

@Suite struct HookAgentTests {
    @Test func agentFromTheRelay() {
        #expect(HookOrigin(["session_id": "s1"]).agent == .claude)
        #expect(HookOrigin(["session_id": "s1", HookWire.agentKey: "codex"]).agent == .codex)
        // An agent this version does not know is taken for Claude Code, not dropped.
        #expect(HookOrigin(["session_id": "s1", HookWire.agentKey: "gemini"]).agent == .claude)
    }

    @Test func claudeKeepsItsIdsOthersArePrefixed() {
        #expect(HookOrigin(["session_id": "s1"]).sessionId == "s1")
        #expect(HookOrigin(["session_id": "s1", HookWire.agentKey: "codex"]).sessionId == "codex:s1")
    }

    @MainActor @Test func sameIdTwoAgentsTwoSessions() {
        let store = SessionStore()
        store.apply(.sessionStart, origin: HookOrigin(["session_id": "s1", "cwd": "/w/shop"]))
        store.apply(.sessionStart, origin: HookOrigin(["session_id": "s1", "cwd": "/w/api", HookWire.agentKey: "codex"]))
        #expect(store.sessions.count == 2)
        #expect(store.session("s1")?.agent == .claude)
        #expect(store.session("codex:s1")?.agent == .codex)
        #expect(store.session("codex:s1")?.projectName == "api")
    }

    @MainActor @Test func codexEventsFromTheSchema() throws {
        let (request, origin) = HookEvent.decode(try codexPayload("codex-permission-request"))
        #expect(origin.agent == .codex)
        #expect(origin.projectName == "api")
        guard case .permissionRequest(let tool, let input, _) = request else { Issue.record("not a permission request"); return }
        #expect(tool == "shell")
        #expect(StepLabel.command(input.value) == "npm test")

        let (stop, _) = HookEvent.decode(try codexPayload("codex-stop"))
        guard case .stop(let message) = stop else { Issue.record("not a stop"); return }
        #expect(message == "Готово, тесты зелёные. Закоммитить?")
        // The answer shows in the session card, as Claude's does.
        let store = SessionStore()
        let session = store.apply(stop, origin: origin)
        #expect(session?.lastMessage == "Готово, тесты зелёные. Закоммитить?")
        #expect(session?.asksBack == true)
    }
}
