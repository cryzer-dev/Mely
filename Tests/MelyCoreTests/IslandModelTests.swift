import Testing
import Foundation
@testable import MelyCore

@MainActor
@Suite struct IslandModelTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func approvalBeatsEverything() {
        let model = IslandModel()
        model.post(IslandItem(id: "music", kind: .nowPlaying, source: "now-playing", title: "Song", createdAt: t0))
        model.post(IslandItem(id: "msg", kind: .message, source: "notifications", title: "Аня", createdAt: t0))
        model.post(IslandItem(id: "work", kind: .agentActivity, source: "claude-code", title: "Edit", createdAt: t0))
        model.post(IslandItem(id: "perm", kind: .approval, source: "claude-code", title: "Bash", createdAt: t0.addingTimeInterval(5)))
        model.post(IslandItem(id: "meet", kind: .meetingSoon, source: "calendar", title: "Стендап", createdAt: t0))
        model.post(IslandItem(id: "ask", kind: .question, source: "claude-code", title: "Какой?", createdAt: t0))
        #expect(model.ordered(now: t0).map(\.id) == ["perm", "ask", "meet", "msg", "music", "work"])
        #expect(model.top(now: t0)?.id == "perm")
        #expect(model.holdsIslandOpen)
    }

    @Test func approvalsKeepArrivalOrder() {
        let model = IslandModel()
        model.post(IslandItem(id: "second", kind: .approval, source: "a", title: "2", createdAt: t0.addingTimeInterval(1)))
        model.post(IslandItem(id: "first", kind: .approval, source: "b", title: "1", createdAt: t0))
        #expect(model.ordered(now: t0).map(\.id) == ["first", "second"])
    }

    @Test func expiredPreviewsDisappear() {
        let model = IslandModel()
        model.post(IslandItem(id: "msg", kind: .message, source: "n", title: "Hi", createdAt: t0, expiresAt: t0.addingTimeInterval(4)))
        #expect(model.top(now: t0.addingTimeInterval(3))?.id == "msg")
        #expect(model.top(now: t0.addingTimeInterval(5)) == nil)
        model.prune(now: t0.addingTimeInterval(5))
        #expect(model.items.isEmpty)
        #expect(!model.holdsIslandOpen)
    }

    @Test func sameIdReplacesAndSourceRemoval() {
        let model = IslandModel()
        model.post(IslandItem(id: "x", kind: .message, source: "n", title: "old", createdAt: t0))
        model.post(IslandItem(id: "x", kind: .message, source: "n", title: "new", createdAt: t0))
        model.post(IslandItem(id: "y", kind: .nowPlaying, source: "m", title: "song", createdAt: t0))
        #expect(model.items.count == 2 && model.items.first?.title == "new")
        model.removeAll(from: "n")
        #expect(model.items.map(\.id) == ["y"])
    }
}
