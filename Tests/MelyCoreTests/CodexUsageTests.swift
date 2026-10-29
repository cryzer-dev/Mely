import Testing
import Foundation
@testable import MelyCore

@Suite struct CodexUsageTests {
    func fixture() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "codex-rate-limits", withExtension: "json", subdirectory: "Fixtures"))
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    @Test func parsesTheSample() throws {
        let now = Date(timeIntervalSince1970: 1_793_600_000)
        let usage = try #require(CodexUsage.parse(try fixture(), now: now))
        #expect(usage.fiveHour?.usedPercent == 42)
        #expect(usage.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_793_635_200))
        #expect(usage.sevenDay?.usedPercent == 70)
        #expect(usage.plan == "plus")
        #expect(usage.resetCredits == 1)
        #expect(usage.updatedAt == now)
    }

    @Test func windowsByLength() {
        // A day or less is the short window, whatever slot it came in.
        let swapped: [String: Any] = ["rateLimits": [
            "primary": ["usedPercent": 10, "windowDurationMins": 10080],
            "secondary": ["usedPercent": 90, "windowDurationMins": 300],
        ]]
        let usage = CodexUsage.parse(swapped)
        #expect(usage?.fiveHour?.usedPercent == 90)
        #expect(usage?.sevenDay?.usedPercent == 10)
        // No lengths: primary is short, secondary the week.
        let bare: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 5], "secondary": ["usedPercent": 6]]]
        #expect(CodexUsage.parse(bare)?.fiveHour?.usedPercent == 5)
        #expect(CodexUsage.parse(bare)?.sevenDay?.usedPercent == 6)
    }

    @Test func noWindowsNoUsage() {
        #expect(CodexUsage.parse(["rateLimits": ["planType": "free"]]) == nil)
        #expect(CodexUsage.parse([:]) == nil)
        // No credits and an unknown plan say nothing.
        let usage = CodexUsage.parse(["rateLimits": ["primary": ["usedPercent": 1], "planType": "unknown"],
                                      "rateLimitResetCredits": ["availableCount": 0]])
        #expect(usage?.plan == nil)
        #expect(usage?.resetCredits == nil)
    }

    @Test func problems() {
        let signedOut = CodexAppServer.Failure.rpc("codex account authentication required to read rate limits")
        #expect(CodexUsage.problem(for: signedOut) == CodexUsage.signedOut)
        #expect(CodexUsage.problem(for: CodexAppServer.Failure.timedOut) == "Нет данных: Codex не ответил за 15 секунд")
    }

    /// A stand-in `codex`: a script that answers request 1 with `reply`, or never answers.
    func fakeCodex(reply: String?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mely-fake-codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("codex")
        let body = reply.map { """
            while IFS= read -r line; do
              case "$line" in *'"id":1'*) printf '%s\\n' '\($0)' ;; esac
            done
            """ } ?? "sleep 30"
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    @Test func readsThroughTheAppServer() async throws {
        let data = try JSONSerialization.data(withJSONObject: ["id": 1, "result": try fixture()])
        let codex = try fakeCodex(reply: String(decoding: data, as: UTF8.self))
        defer { try? FileManager.default.removeItem(at: codex.deletingLastPathComponent()) }
        let usage = try await CodexUsage.read(codex: codex, timeout: 5)
        #expect(usage?.fiveHour?.usedPercent == 42)
    }

    @Test func signedOutComesBackAsRPCError() async throws {
        let codex = try fakeCodex(reply: #"{"id":1,"error":{"code":-32600,"message":"codex account authentication required to read rate limits"}}"#)
        defer { try? FileManager.default.removeItem(at: codex.deletingLastPathComponent()) }
        await #expect(throws: CodexAppServer.Failure.rpc("codex account authentication required to read rate limits")) {
            _ = try await CodexUsage.read(codex: codex, timeout: 5)
        }
    }

    @Test func silentCodexTimesOut() async throws {
        let codex = try fakeCodex(reply: nil)
        defer { try? FileManager.default.removeItem(at: codex.deletingLastPathComponent()) }
        let start = Date()
        await #expect(throws: CodexAppServer.Failure.timedOut) { _ = try await CodexUsage.read(codex: codex, timeout: 0.5) }
        #expect(Date().timeIntervalSince(start) < 5)
    }
}

@Suite struct CodexUsagePollTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func onlyWhileOnScreen() {
        #expect(!CodexUsagePoll.isDue(last: nil, now: now, visibility: .hidden))
        #expect(CodexUsagePoll.isDue(last: nil, now: now, visibility: .open))
        // Open: once a minute.
        #expect(!CodexUsagePoll.isDue(last: now.addingTimeInterval(-59), now: now, visibility: .open))
        #expect(CodexUsagePoll.isDue(last: now.addingTimeInterval(-60), now: now, visibility: .open))
        // Only in the wing: once in 5 minutes.
        #expect(!CodexUsagePoll.isDue(last: now.addingTimeInterval(-120), now: now, visibility: .wing))
        #expect(CodexUsagePoll.isDue(last: now.addingTimeInterval(-300), now: now, visibility: .wing))
        #expect(!CodexUsagePoll.isDue(last: now.addingTimeInterval(-3600), now: now, visibility: .hidden))
    }
}
