import Testing
import Foundation
@testable import MelyCore

/// A responder over a socket pair: `read()` returns what the app replied.
private final class Pipe {
    let responder: HookResponder
    private let peer: Int32

    init() {
        var fds: [Int32] = [0, 0]
        socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        // As the server does: replying to a hung-up hook must not raise SIGPIPE.
        var on: Int32 = 1
        setsockopt(fds[0], SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        responder = HookResponder(fd: fds[0])
        peer = fds[1]
    }

    func read() -> HookDecision? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = recv(peer, &buffer, buffer.count, MSG_DONTWAIT)
        guard n > 0 else { return nil }
        return HookDecision(line: String(decoding: buffer[..<n], as: UTF8.self).trimmingCharacters(in: .newlines))
    }

    /// `nc-hook` gave up waiting.
    func hangUp() { close(peer) }
}

@MainActor
@Suite struct ApprovalQueueTests {
    let store = SessionStore()

    func session(_ id: String, _ cwd: String) -> ClaudeSession {
        store.apply(.sessionStart, origin: HookOrigin(["session_id": id, "cwd": cwd,
                                                         "host_bundle_id": "com.jetbrains.WebStorm"]))!
    }

    func bash(_ command: String, suggestions: [Any] = []) -> HookEvent {
        .permissionRequest(tool: "Bash", input: JSONObject(["command": command]),
                           suggestions: JSONObject(["items": suggestions]))
    }

    static let twoQuestions: [String: Any] = ["questions": [
        ["question": "Какую библиотеку взять?", "header": "Библиотека", "multiSelect": false,
         "options": [["label": "zod", "description": "схемы"], ["label": "yup"]]],
        ["question": "Что покрыть тестами?", "header": "Тесты", "multiSelect": true,
         "options": [["label": "корзину"], ["label": "оплату"], ["label": "доставку"]]],
    ]]

    @Test func codexRequestHasNoAlwaysAndGoesWhenTheHookGivesUp() {
        let queue = ApprovalQueue()
        let pipe = Pipe()
        let codex = store.apply(.sessionStart, origin: HookOrigin(["session_id": "c", "cwd": "/w/api", HookWire.agentKey: "codex"]))!
        let request = queue.enqueue(bash("npm test", suggestions: [["type": "addRules"]]), session: codex, responder: pipe.responder)
        guard case .approval(_, _, _, let canAlways)? = request?.kind else { Issue.record("no card"); return }
        #expect(!canAlways)
        #expect(request?.sessionId == "codex:c")
        // 120 s later Codex stops waiting and `nc-hook` hangs up: the card goes, Codex asks in the terminal.
        pipe.hangUp()
        #expect(queue.sweep().map(\.id) == [request?.id])
        #expect(queue.requests.isEmpty)
    }

    @Test func requestsFromTwoSessionsQueueInOrder() {
        let queue = ApprovalQueue()
        let a = Pipe(), b = Pipe()
        let first = queue.enqueue(bash("npm run build"), session: session("a", "/w/shop"), responder: a.responder)
        queue.enqueue(bash("rm -rf dist", suggestions: [["type": "addRules"]]), session: session("b", "/w/admin"),
                      responder: b.responder)
        #expect(queue.requests.count == 2)
        #expect(queue.current == first)
        #expect(queue.current?.kind == .approval(tool: "Bash", title: queue.current!.approvalTitle,
                                                 detail: "npm run build", canAlways: false))
        if case .approval(_, _, _, let canAlways) = queue.requests[1].kind { #expect(canAlways) }

        queue.resolve(first!.id, with: .allow)
        #expect(a.read() == .allow)
        #expect(queue.current?.projectName == "admin")
        #expect(b.read() == nil)  // nothing is allowed without a click
        queue.resolve(queue.current!.id, with: .deny)
        #expect(b.read() == .deny)
        #expect(queue.requests.isEmpty)
    }

    @Test func answeredInTerminalDropsTheCard() {
        let queue = ApprovalQueue()
        let s = session("a", "/w/shop")
        queue.enqueue(bash("npm test"), session: s, responder: Pipe().responder)
        // Unrelated events (the permission Notification, another tool starting) keep it.
        #expect(queue.settle(after: .notification(type: "permission_prompt", message: ""), session: "a").isEmpty)
        #expect(queue.settle(after: .toolFinished(tool: "Read", input: JSONObject([:]), failed: false), session: "b").isEmpty)
        let dropped = queue.settle(after: .toolFinished(tool: "Bash", input: JSONObject([:]), failed: false), session: "a")
        #expect(dropped.count == 1)
        #expect(queue.requests.isEmpty)
    }

    @Test func hookTimeoutDropsTheCardOnSweep() {
        let queue = ApprovalQueue()
        let alive = Pipe(), gone = Pipe()
        queue.enqueue(bash("a"), session: session("a", "/w/shop"), responder: alive.responder)
        queue.enqueue(bash("b"), session: session("b", "/w/admin"), responder: gone.responder)
        #expect(queue.sweep().isEmpty)
        gone.hangUp()
        #expect(queue.sweep().map(\.sessionId) == ["b"])
        #expect(queue.requests.map(\.sessionId) == ["a"])
    }

    @Test func parsesQuestions() throws {
        let payload = try #require(QuestionPayload(Self.twoQuestions))
        #expect(payload.questions.count == 2)
        #expect(payload.questions[0].header == "Библиотека")
        #expect(payload.questions[0].options[0].description == "схемы")
        #expect(payload.questions[0].options[1].description == nil)
        #expect(payload.questions[1].multiSelect)
        #expect(!payload.answersWithOneClick)
        #expect(QuestionPayload(["questions": []]) == nil)
        #expect(QuestionPayload(["questions": [["question": "Да?", "options": [["label": "да"]]]]])?.answersWithOneClick == true)
    }

    @Test func multiSelectAnswerReachesClaudeCode() throws {
        let queue = ApprovalQueue()
        let pipe = Pipe()
        let request = try #require(queue.enqueue(.question(input: JSONObject(Self.twoQuestions)),
                                                 session: session("a", "/w/shop"), responder: pipe.responder))
        let answers: [String: HookDecision.AnswerValue] = [
            "Какую библиотеку взять?": .single("zod"),
            "Что покрыть тестами?": .multiple(["корзину", "оплату"]),
        ]
        queue.resolve(request.id, with: .answer(answers))
        let decision = try #require(pipe.read())
        #expect(decision == .answer(answers))
        let output = try #require(decision.hookOutput(event: "PreToolUse", payload: ["tool_input": Self.twoQuestions]))
        #expect(output.contains("\"answers\""))
        #expect(output.contains("корзину"))
    }

    @Test func sameQuestionTwiceIsOneCard() {
        let queue = ApprovalQueue()
        let s = session("a", "/w/shop")
        let first = Pipe()
        queue.enqueue(.question(input: JSONObject(Self.twoQuestions)), session: s, responder: first.responder)
        queue.enqueue(.question(input: JSONObject(Self.twoQuestions)), session: s, responder: Pipe().responder)
        #expect(queue.requests.count == 1)
        #expect(first.read() == .ask)  // the earlier hook falls back to the terminal
    }
}

private extension PendingRequest {
    var approvalTitle: String {
        if case .approval(_, let title, _, _) = kind { return title }
        return ""
    }
}
