import Testing
import Foundation
import MelyCore
import MelyUI

/// One agent on: nothing names it; several: the switcher's choice and the pin.
@MainActor @Suite struct AgentsModelTests {
    func model(_ on: [Agent], defaults name: String = #function) -> (AgentsModel, UserDefaults) {
        let defaults = UserDefaults(suiteName: "mely-tests-agents-\(name)")!
        defaults.removePersistentDomain(forName: "mely-tests-agents-\(name)")
        let usage: [Agent: PlanUsageStore] = [.claude: PlanUsageStore(agent: .claude, defaults: defaults),
                                              .codex: PlanUsageStore(agent: .codex, defaults: defaults)]
        return (AgentsModel(usage: usage, defaults: defaults) { on.contains($0) }, defaults)
    }

    @Test func oneAgentIsNotMulti() {
        let (codexOnly, _) = model([.codex])
        #expect(!codexOnly.isMulti)
        #expect(codexOnly.tabAgent == .codex)
        #expect(codexOnly.shownAgent == .codex)
        #expect(codexOnly.shownUsage?.agent == .codex)
    }

    @Test func noneOnCountsAsClaude() {
        let (none, _) = model([])
        #expect(none.enabled == [.claude])
        #expect(!none.isMulti)
    }

    @Test func choiceAndPinAreKept() {
        let (agents, defaults) = model([.claude, .codex])
        #expect(agents.isMulti)
        #expect(agents.tabAgent == .claude)
        agents.selected = .codex
        agents.pinned = .codex
        let again = AgentsModel(usage: [:], defaults: defaults) { _ in true }
        #expect(again.tabAgent == .codex)
        #expect(again.shownAgent == .codex)
    }

    @Test func switchedOffChoiceFallsBack() {
        let (agents, _) = model([.claude])
        agents.selected = .codex
        agents.pinned = .codex
        #expect(agents.tabAgent == .claude)
        #expect(agents.shownAgent == .claude)
    }

    @Test func changesAreReported() {
        let (agents, _) = model([.claude, .codex])
        var count = 0
        agents.onChange = { count += 1 }
        agents.pinned = .codex
        agents.cardOpen = true
        agents.cardOpen = true
        agents.appeared()
        #expect(count == 3)
    }
}
