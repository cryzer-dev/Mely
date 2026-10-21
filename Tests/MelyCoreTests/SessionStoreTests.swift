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

    @Test func keepsTheProcessOfTheSession() {
        let store = SessionStore()
        var p = ["session_id": "a", "cwd": "/w/shop"] as [String: Any]
        store.apply(.sessionStart, origin: HookOrigin(p), now: t0)
        #expect(store.session("a")?.origin.process == nil)
        p["claude_pid"] = 4242
        p["claude_start"] = 1_700_000_000.5
        store.apply(.userPrompt("hi"), origin: HookOrigin(p), now: t0)
        #expect(store.session("a")?.origin.process == ProcessIdentity(pid: 4242, start: 1_700_000_000.5))
        // `claude --resume` continues the session in another process.
        p["claude_pid"] = 5151
        store.apply(.userPrompt("again"), origin: HookOrigin(p), now: t0)
        #expect(store.session("a")?.origin.process?.pid == 5151)
        // An event without the process (an older relay) keeps the known one.
        store.apply(.stop(lastMessage: nil), origin: HookOrigin(["session_id": "a"]), now: t0)
        #expect(store.session("a")?.origin.process?.pid == 5151)
    }
}

@Suite struct ProcessIdentityTests {
    @Test func skipsShellsToTheClaudeProcess() {
        let sh = ProcessIdentity(pid: 30, start: 3), node = ProcessIdentity(pid: 20, start: 2)
        #expect(ProcessIdentity.claude(among: [(sh, "sh"), (ProcessIdentity(pid: 25, start: 2.5), "zsh"), (node, "node")]) == node)
        #expect(ProcessIdentity.claude(among: [(node, "2.1.304")]) == node)
        #expect(ProcessIdentity.claude(among: [(sh, "bash")]) == nil)
        #expect(ProcessIdentity.claude(among: []) == nil)
    }

    /// A WebStorm tab closed: its Claude Code stays half-exited (`?Es`, `P_WEXIT`), never reaped.
    @Test func halfExitedIsGone() {
        #expect(ProcessIdentity.isEnding(stat: 2, flags: 0x6006))
        #expect(!ProcessIdentity.isEnding(stat: 2, flags: 0x4006))
        #expect(ProcessIdentity.isEnding(stat: 5, flags: 0))
    }

    @Test func aliveDeadAndReusedPids() throws {
        let me = try #require(ProcessIdentity.running(ProcessInfo.processInfo.processIdentifier)?.identity)
        #expect(me.isAlive())
        // The same pid started at another time is another process.
        #expect(!ProcessIdentity(pid: me.pid, start: me.start - 60).isAlive())

        let done = Process()
        done.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try done.run()
        let pid = done.processIdentifier
        done.waitUntilExit()
        #expect(!ProcessIdentity(pid: pid, start: me.start).isAlive())

        #expect(ProcessIdentity(pid: 7, start: 100).isAlive { $0 == 7 ? 100.2 : nil })
        #expect(!ProcessIdentity(pid: 7, start: 100).isAlive { _ in nil })
    }
}
