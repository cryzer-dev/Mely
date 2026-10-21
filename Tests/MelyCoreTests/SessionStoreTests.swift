import Testing
import Foundation
@testable import MelyCore

@MainActor
@Suite struct SessionStoreTests {
    let t0 = Date(timeIntervalSince1970: 2_000_000)

    func origin(_ id: String, _ cwd: String, host: String = "com.jetbrains.WebStorm") -> HookOrigin {
        HookOrigin(["session_id": id, "cwd": cwd, "host_bundle_id": host])
    }

    @Test func twoProjectsInOneIDEAreTwoSessions() {
        let store = SessionStore()
        store.apply(.sessionStart, origin: origin("a", "/w/shop"), now: t0)
        store.apply(.sessionStart, origin: origin("b", "/w/admin"), now: t0)
        #expect(store.sessions.map(\.projectName) == ["shop", "admin"])
        #expect(store.sessions.allSatisfy { $0.host.name == "WebStorm" })
    }

    @Test func turnLifecycle() {
        let store = SessionStore()
        let o = origin("a", "/w/shop")
        store.apply(.userPrompt("почини корзину"), origin: o, now: t0)
        #expect(store.session("a")?.state == .thinking)
        store.apply(.toolStarted(tool: "Edit", input: JSONObject(["file_path": "/w/shop/Cart.tsx"])), origin: o, now: t0)
        #expect(store.session("a")?.step == "Правит · Cart.tsx")
        let input = JSONObject(["file_path": "/w/shop/Cart.tsx", "old_string": "a\nb\n", "new_string": "a\nc\nd\n"])
        store.apply(.toolFinished(tool: "Edit", input: input, failed: false), origin: o, now: t0)
        #expect(store.session("a")?.addedLines == 2 && store.session("a")?.removedLines == 1)
        store.apply(.stop(lastMessage: "**Готово.** Корзина починена.\n\nДетали…"), origin: o, now: t0)
        #expect(store.session("a")?.state == .finished(summary: "Готово. Корзина починена."))
        store.settle("a")
        #expect(store.session("a")?.state == .idle)
        store.apply(.sessionEnd, origin: o, now: t0)
        #expect(store.sessions.isEmpty)
    }

    @Test func approvalThenResume() {
        let store = SessionStore()
        let o = origin("a", "/w/shop")
        store.apply(.permissionRequest(tool: "Bash", input: JSONObject(["command": "npm test"]), suggestions: JSONObject([:])),
                    origin: o, now: t0)
        #expect(store.session("a")?.state == .waitingApproval)
        #expect(store.session("a")?.step == "Тестирует · npm test")
        store.apply(.toolFinished(tool: "Bash", input: JSONObject([:]), failed: false), origin: o, now: t0)
        #expect(store.session("a")?.state == .waitingApproval)
        store.resumeWork("a")
        #expect(store.session("a")?.state == .working)
    }

    @Test func rateLimitAndErrors() {
        let store = SessionStore()
        store.apply(.notification(type: "", message: "Claude usage limit reached. Resets at 5pm"), origin: origin("a", "/w"), now: t0)
        #expect(store.session("a")?.state == .rateLimited)
        store.apply(.stopFailure("overloaded"), origin: origin("b", "/w"), now: t0)
        #expect(store.session("b")?.state == .error("overloaded"))
    }

    @Test func silenceRules() {
        let store = SessionStore()
        store.apply(.toolStarted(tool: "Read", input: JSONObject([:])), origin: origin("a", "/w"), now: t0)
        store.sweep(now: t0.addingTimeInterval(31 * 60))
        #expect(store.session("a")?.state == .idle)
        store.sweep(now: t0.addingTimeInterval(13 * 3600))
        #expect(store.sessions.isEmpty)
    }

    @Test func stepLabels() {
        #expect(StepLabel.label(tool: "Bash", input: ["command": "cat README.md"]) == "Читает · cat README.md")
        #expect(StepLabel.label(tool: "Grep", input: ["pattern": "TODO"]) == "Ищет · TODO")
        #expect(StepLabel.label(tool: "mcp__github__create_pr", input: [:]) == "github · create_pr")
        #expect(StepLabel.label(tool: "Unknown", input: [:]) == "Unknown")
    }
}
