import Testing
@testable import MelyCore

/// Whose limits the notch's one ring shows (openspec plan-usage «Чей лимит в челке»).
@Suite struct UsagePinTests {
    @Test func firstOnByDefault() {
        #expect(UsagePin.shown(enabled: [.claude, .codex], pinned: nil) == .claude)
        #expect(UsagePin.shown(enabled: [.codex], pinned: nil) == .codex)
    }

    @Test func pinnedWhileOn() {
        #expect(UsagePin.shown(enabled: [.claude, .codex], pinned: .codex) == .codex)
    }

    @Test func pinnedSwitchedOffFallsBackToFirst() {
        #expect(UsagePin.shown(enabled: [.claude], pinned: .codex) == .claude)
    }

    @Test func noneOn() {
        #expect(UsagePin.shown(enabled: [], pinned: .codex) == nil)
    }

    @Test func agentsByIntegration() {
        for agent in Agent.allCases { #expect(Agent(integrationId: agent.integrationId) == agent) }
        #expect(Agent(integrationId: "calendar") == nil)
    }
}
