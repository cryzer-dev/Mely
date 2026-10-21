import Testing
import Foundation
@testable import MelyCore

@Suite(.serialized) struct HookServerTests {
    final class Box: @unchecked Sendable {
        let lock = NSLock()
        var payloads: [[String: Any]] = []
        var responders: [HookResponder] = []
    }

    private func path() -> String { "/tmp/mely-srv-\(UUID().uuidString.prefix(8)).sock" }

    @Test func fireAndForgetAndBlocking() throws {
        let p = path()
        let box = Box()
        let server = HookSocketServer(path: p) { payload, responder in
            box.lock.lock()
            box.payloads.append(payload)
            if let responder { box.responders.append(responder) }
            box.lock.unlock()
            responder?.reply(.deny)
        }
        try server.start()
        defer { server.stop() }

        let event = #"{"hook_event_name":"PreToolUse","tool_name":"Edit","session_id":"s1"}"#
        #expect(UnixSocketClient.send(event, to: p, timeout: 1, waitForReply: false) == "")

        let perm = #"{"hook_event_name":"PermissionRequest","tool_name":"Bash","session_id":"s1"}"#
        let reply = UnixSocketClient.send(perm, to: p, timeout: 2, waitForReply: true)
        #expect(reply.map(HookDecision.init(line:)) == .deny)

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            box.lock.lock(); let n = box.payloads.count; box.lock.unlock()
            if n == 2 { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        box.lock.lock(); defer { box.lock.unlock() }
        #expect(box.payloads.count == 2)
        #expect(box.responders.count == 1)
        #expect(!box.responders[0].isPending)
    }

    @Test func socketIsOwnerOnly() throws {
        let p = path()
        let server = HookSocketServer(path: p) { _, _ in }
        try server.start()
        defer { server.stop() }
        let mode = (try FileManager.default.attributesOfItem(atPath: p)[.posixPermissions] as? NSNumber)?.intValue
        #expect(mode == 0o600)
    }
}

@Suite struct HookEventTests {
    @Test func decodesClaudeEvents() {
        let base: [String: Any] = ["session_id": "abc", "cwd": "/Users/me/shop", "host_bundle_id": "com.jetbrains.WebStorm"]
        func ev(_ extra: [String: Any]) -> HookEvent { HookEvent.decode(base.merging(extra) { $1 }).0 }

        if case .toolStarted(let tool, let input) = ev(["hook_event_name": "PreToolUse", "tool_name": "Edit",
                                                        "tool_input": ["file_path": "/a/Cart.tsx"]]) {
            #expect(tool == "Edit" && input["file_path"] as? String == "/a/Cart.tsx")
        } else { Issue.record("PreToolUse") }

        if case .toolFinished(_, _, let failed) = ev(["hook_event_name": "PostToolUseFailure", "tool_name": "Bash"]) {
            #expect(failed)
        } else { Issue.record("PostToolUseFailure") }

        if case .question = ev(["hook_event_name": "PermissionRequest", "tool_name": "AskUserQuestion"]) {} else {
            Issue.record("AskUserQuestion via PermissionRequest")
        }
        if case .question = ev(["mely_kind": "ask_user_question", "tool_name": "AskUserQuestion"]) {} else {
            Issue.record("--ask")
        }
        if case .statusLine = ev(["mely_kind": "statusline", "rate_limits": [:]]) {} else { Issue.record("statusline") }
        if case .unknown("Mystery") = ev(["hook_event_name": "Mystery"]) {} else { Issue.record("unknown") }

        let origin = HookEvent.decode(base).1
        #expect(origin.projectName == "shop")
        #expect(origin.hostBundleId == "com.jetbrains.WebStorm")
        #expect(HookEvent.decode([:]).1.sessionId == "unknown")
    }
}
