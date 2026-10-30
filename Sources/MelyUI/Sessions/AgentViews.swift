import SwiftUI
import MelyCore

/// The agents on in the notch, whose sessions the «Агенты» tab shows and whose limits
/// the ring shows. With one agent on, nothing in the notch names it.
@MainActor
@Observable
public final class AgentsModel {
    /// Whether an agent is on (its integration in the registry): read through, so views
    /// follow the switches.
    @ObservationIgnored private let isEnabled: (Agent) -> Bool
    /// The limits of each agent.
    @ObservationIgnored private let stores: [Agent: PlanUsageStore]
    @ObservationIgnored private let defaults: UserDefaults
    /// The «Агенты» tab's agent, chosen in the switcher or by an event opening the island.
    public var selected: Agent? {
        didSet { defaults.set(selected?.rawValue, forKey: Self.selectedKey); changed() }
    }
    /// The agent pinned in the notch from the limits card; nil: the first one on.
    public var pinned: Agent? {
        didSet { defaults.set(pinned?.rawValue, forKey: Self.pinnedKey); changed() }
    }
    /// The limits card under the header's ring is open.
    public var cardOpen = false {
        didSet { if cardOpen != oldValue { changed() } }
    }
    /// Something about which limits show changed (the island opened, a pin, a tab).
    @ObservationIgnored public var onChange: (() -> Void)?

    static let selectedKey = "agents.selected"
    static let pinnedKey = "agents.pinned"

    public init(usage: [Agent: PlanUsageStore], defaults: UserDefaults = .standard,
                isEnabled: @escaping (Agent) -> Bool) {
        self.stores = usage
        self.defaults = defaults
        self.isEnabled = isEnabled
        selected = defaults.string(forKey: Self.selectedKey).flatMap(Agent.init(rawValue:))
        pinned = defaults.string(forKey: Self.pinnedKey).flatMap(Agent.init(rawValue:))
    }

    /// The agents on, in the settings' order; none on counts as Claude Code, as before agents.
    public var enabled: [Agent] {
        let on = Agent.allCases.filter(isEnabled)
        return on.isEmpty ? [.claude] : on
    }

    /// More than one agent on: the switcher, the dots, the pin and the names show.
    public var isMulti: Bool { enabled.count > 1 }

    /// The «Агенты» tab's agent: the chosen one while it is on, otherwise the first.
    public var tabAgent: Agent {
        if let selected, enabled.contains(selected) { return selected }
        return enabled[0]
    }

    /// Whose limits the ring shows.
    public var shownAgent: Agent { UsagePin.shown(enabled: enabled, pinned: pinned) ?? .claude }

    public func usage(_ agent: Agent) -> PlanUsageStore? { stores[agent] }

    public var shownUsage: PlanUsageStore? { stores[shownAgent] }

    /// The island opened: the limits on screen may be due.
    public func appeared() { changed() }

    private func changed() { onChange?() }
}

/// An agent's colour: a label, not a state.
public enum AgentStyle {
    public static func color(_ agent: Agent) -> Color {
        switch agent {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(white: 0.88)
        }
    }
}

/// A small dot in the agent's colour.
struct AgentDot: View {
    let agent: Agent
    var size: CGFloat = 7

    var body: some View {
        Circle().fill(AgentStyle.color(agent)).frame(width: size, height: size)
    }
}

/// «● Claude Code 2 | ● Codex 1» over the «Агенты» tab, with two agents or more on. An agent
/// not shown that waits for an answer gets a dot in the request's colour.
struct AgentSwitcher: View {
    let agents: AgentsModel
    let sessions: [ClaudeSession]
    let requests: [PendingRequest]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(agents.enabled, id: \.self) { agent in
                segment(agent)
            }
        }
        .padding(2)
        .background(.white.opacity(MelyFill.card), in: Capsule())
        .layoutProbe("agents.switcher", inside: "content")
    }

    private func segment(_ agent: Agent) -> some View {
        let isOn = agents.tabAgent == agent
        let count = sessions.filter { $0.agent == agent }.count
        let waiting = !isOn ? requests.first { $0.agent == agent } : nil
        return Button {
            MelyHaptics.tap()
            withAnimation(MelyMotion.tab) { agents.selected = agent }
        } label: {
            HStack(spacing: 6) {
                AgentDot(agent: agent)
                Text(agent.title).font(.system(size: MelyType.footnote, weight: .semibold))
                    .lineLimit(1).fixedSize()
                if count > 0 {
                    Text("\(count)").font(.system(size: MelyType.caption, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(.white.opacity(MelyInk.secondary))
                }
                if let waiting {
                    Circle().fill(SessionStateStyle.color(waiting.isQuestion ? .waitingAnswer : .waitingApproval))
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(.white.opacity(isOn ? 1 : MelyInk.strong))
            .padding(.horizontal, 10).frame(height: 22)
            .background(.white.opacity(isOn ? MelyFill.selected : 0), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(agent.title), сессий: \(count)" + (waiting != nil ? ", ждёт ответа" : ""))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .layoutProbe("agents.switcher.\(agent.rawValue)", row: "agents.switcher", inside: "agents.switcher")
    }
}
