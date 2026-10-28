import Testing
import Foundation
@testable import MelyCore

@Suite struct IslandWingsTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func eventShowsWingsForAFewSeconds() {
        var wings = IslandWings()
        #expect(!wings.showsWings(hovering: false, pinned: false, now: t0))
        wings.flash(now: t0)
        #expect(wings.showsWings(hovering: false, pinned: false, now: t0.addingTimeInterval(4)))
        #expect(!wings.showsWings(hovering: false, pinned: false, now: t0.addingTimeInterval(5.1)))
        // A second event extends, never shortens.
        wings.flash(now: t0.addingTimeInterval(3))
        #expect(wings.showsWings(hovering: false, pinned: false, now: t0.addingTimeInterval(7)))
    }

    @Test func hoverAndWaitingRequestsKeepThem() {
        let wings = IslandWings()
        #expect(wings.showsWings(hovering: true, pinned: false, now: t0))
        #expect(wings.showsWings(hovering: false, pinned: true, now: t0))
    }

    @Test func modes() {
        var wings = IslandWings()
        // While active: as long as something is live, flash or not.
        #expect(wings.showsWings(hovering: false, pinned: false, live: true, mode: .whileActive, now: t0))
        #expect(!wings.showsWings(hovering: false, pinned: false, live: false, mode: .whileActive, now: t0))
        // Flash: live alone is not enough.
        #expect(!wings.showsWings(hovering: false, pinned: false, live: true, mode: .flash, now: t0))
        wings.flash(now: t0)
        #expect(wings.showsWings(hovering: false, pinned: false, live: false, mode: .whileActive, now: t0))
        // Hover only: neither events nor activity, but a waiting request still shows.
        #expect(!wings.showsWings(hovering: false, pinned: false, live: true, mode: .hoverOnly, now: t0))
        #expect(wings.showsWings(hovering: false, pinned: true, live: false, mode: .hoverOnly, now: t0))
        #expect(IslandWings.Mode.default == .whileActive)
    }

    @Test func whatCountsAsLive() {
        #expect(IslandWings.live(states: [.idle, .working], usage: nil, now: t0))
        #expect(IslandWings.live(states: [.waitingApproval], usage: nil, now: t0))
        #expect(!IslandWings.live(states: [.idle, .finished(summary: "")], usage: nil, now: t0))
        let near = PlanUsage(fiveHour: PlanWindow(usedPercent: 85, resetsAt: t0.addingTimeInterval(3600)), sevenDay: nil, updatedAt: t0)
        #expect(IslandWings.live(states: [], usage: near, now: t0))
        // A focus session, paused or not, and its break; not the time after it ended.
        var focus = FocusTimer()
        #expect(!IslandWings.live(states: [], usage: nil, focus: focus, now: t0))
        focus.start(now: t0, duration: 60)
        #expect(IslandWings.live(states: [], usage: nil, focus: focus, now: t0))
        focus.pause(now: t0)
        #expect(IslandWings.live(states: [], usage: nil, focus: focus, now: t0))
        focus.resume(now: t0)
        focus.tick(now: t0.addingTimeInterval(60), idleSeconds: 0)
        #expect(!IslandWings.live(states: [], usage: nil, focus: focus, now: t0))
        focus.takeBreak(now: t0)
        #expect(IslandWings.live(states: [], usage: nil, focus: focus, now: t0))
    }

    @Test func onlyANewTurnFlashes() {
        #expect(IslandWings.startsTurn(from: nil, to: .thinking))
        #expect(IslandWings.startsTurn(from: .idle, to: .thinking))
        #expect(IslandWings.startsTurn(from: .finished(summary: ""), to: .working))
        #expect(!IslandWings.startsTurn(from: .thinking, to: .working))
        #expect(!IslandWings.startsTurn(from: .working, to: .working))
        #expect(!IslandWings.startsTurn(from: .working, to: .finished(summary: "")))
    }
}
