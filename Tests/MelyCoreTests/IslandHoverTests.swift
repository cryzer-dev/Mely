// Portions © 2026 Louis Raillé, MIT License — see THIRD_PARTY_NOTICES.md.
import Testing
import Foundation
@testable import MelyCore

@MainActor
@Suite(.serialized) struct IslandHoverTests {
    private func machine() -> IslandStateMachine {
        let m = IslandStateMachine()
        m.openOnHover = true
        m.hoverCloseDelay = 0.3
        return m
    }

    private func waitFor(_ s: IslandStateMachine.State, _ m: IslandStateMachine, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while m.state != s && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(m.state == s)
    }

    @Test func hoverOnlyPeeksByDefault() {
        let off = IslandStateMachine()
        off.mouseEntered()
        #expect(off.state == .compact)
    }

    @Test func hoverOpensAndFoldsAfterGrace() async throws {
        let on = machine()
        on.mouseEntered()
        #expect(on.state == .expanded && on.openedByHover)
        on.mouseLeft()
        #expect(on.state == .expanded)
        try await waitFor(.compact, on)
        #expect(!on.openedByHover)
    }

    @Test func neverCollapseKeepsItOpenAfterThePointerLeaves() async throws {
        let defaults = try #require(UserDefaults(suiteName: "mely-behavior-\(UUID().uuidString)"))
        let behavior = IslandBehavior(defaults: defaults)
        #expect(behavior.collapseAfter == 15 && behavior.hideAfter == 60 && behavior.launchGreeting)
        behavior.collapseAfter = IslandBehavior.never
        behavior.hideAfter = IslandBehavior.never
        let m = IslandStateMachine()
        m.expandedToCompactDelay = 0.05
        m.compactToHiddenDelay = 0.05
        behavior.apply(to: m)
        m.click()
        m.mouseLeft()
        try await Task.sleep(for: .milliseconds(200))
        #expect(m.state == .expanded)
        // «×»: folds, and the compact island stays too.
        m.collapse()
        m.mouseLeft()
        try await Task.sleep(for: .milliseconds(200))
        #expect(m.state == .compact)
        // Saved, and a number again works as before.
        #expect(IslandBehavior(defaults: defaults).collapseAfter == IslandBehavior.never)
        behavior.collapseAfter = 3
        behavior.apply(to: m)
        #expect(m.collapsesWhenLeft && m.expandedToCompactDelay == 3)
    }

    @Test func comingBackKeepsItOpen() async throws {
        let back = machine()
        back.mouseEntered()
        back.mouseLeft()
        back.mouseEntered()
        try await Task.sleep(for: .milliseconds(600))
        #expect(back.state == .expanded)
    }

    @Test func clickInsideAppliesNormalDelay() async throws {
        let clicked = machine()
        clicked.expandedToCompactDelay = 3
        clicked.mouseEntered()
        clicked.userInteracted()
        clicked.mouseLeft()
        try await Task.sleep(for: .milliseconds(600))
        #expect(clicked.state == .expanded)
        clicked.expandedToCompactDelay = 0.05
        try await waitFor(.compact, clicked)
    }

    @Test func pendingApprovalHoldsIsland() async throws {
        let held = machine()
        held.isHeldOpen = { true }
        held.mouseEntered()
        #expect(held.state == .expanded && !held.openedByHover)
        held.mouseLeft()
        try await Task.sleep(for: .milliseconds(600))
        #expect(held.state == .expanded)
    }

    @Test func alertOpenedIslandKeepsNormalDelay() async throws {
        let alert = machine()
        alert.expandedToCompactDelay = 3
        alert.openedExternally()
        alert.mouseEntered()
        alert.mouseLeft()
        try await Task.sleep(for: .milliseconds(600))
        #expect(alert.state == .expanded)
    }
}
