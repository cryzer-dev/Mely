import SwiftUI
import MelyCore

enum PlanUsageStyle {
    /// Green with room to spare, yellow past half, orange from the warning level, red from 90%.
    static func color(_ percent: Double) -> Color {
        if percent >= 90 { return Color(red: 1.0, green: 0.38, blue: 0.35) }
        if percent >= PlanUsage.warningPercent { return Color(red: 1.0, green: 0.58, blue: 0.2) }
        if percent >= 50 { return Color(red: 1.0, green: 0.8, blue: 0.25) }
        return Color(red: 0.3, green: 0.8, blue: 0.45)
    }
}

/// Both plan windows: how full, and when they reset. Shown in the overview header.
public struct PlanUsageGauge: View {
    let usage: PlanUsage?
    /// Why there are no numbers (Codex signed out): the tooltip of «нет данных».
    let problem: String?

    public init(usage: PlanUsage?, problem: String? = nil) {
        self.usage = usage
        self.problem = problem
    }

    public var body: some View {
        // Countdowns move; a minute is precise enough.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let usage = usage?.current(now: context.date) {
                // Old values are dimmed, not labelled: the age does not fit the bar, so it is
                // in the tooltip and spelled out in the card.
                let stale = usage.isStale(now: context.date)
                HStack(spacing: 12) {
                    if let w = usage.fiveHour { window("5 ч", w, now: context.date).fixedSize() }
                    if let w = usage.sevenDay { window("Неделя", w, now: context.date).fixedSize() }
                }
                .opacity(stale ? 0.5 : 1)
                .help(stale ? usage.ageText(now: context.date) : "")
                .layoutProbe("plan.overview", inside: "sessions.usage")
            } else {
                Text("Лимиты: нет данных").font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                    .help(problem ?? "")
            }
        }
    }

    private func window(_ title: String, _ w: PlanWindow, now: Date) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: MelyType.caption, weight: .medium)).foregroundStyle(.white.opacity(MelyInk.secondary))
            Capsule().fill(.white.opacity(MelyFill.selected))
                .frame(width: 44, height: 5)
                .overlay(alignment: .leading) {
                    Capsule().fill(PlanUsageStyle.color(w.usedPercent))
                        .frame(width: 44 * min(1, max(0.04, w.usedPercent / 100)), height: 5)
                }
            Text("\(Int(w.usedPercent.rounded()))%")
                .font(.system(size: MelyType.footnote, weight: .semibold, design: .monospaced))
                .foregroundStyle(w.isWarning ? PlanUsageStyle.color(w.usedPercent) : .white)
            if let reset = w.resetsAt {
                Text("· \(PlanUsage.countdown(to: reset, from: now))")
                    .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.secondary))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Лимит \(title): \(Int(w.usedPercent.rounded())) процентов")
    }
}

/// Compact island: the five-hour window as a ring and its percent; a window used up
/// shows when it comes back instead (`PlanUsage.compactWindow`). Nothing to show: nothing,
/// or with `showsEmpty` (the header's pill, which must not stand empty) a dim ring and «—».
public struct CompactPlanGauge: View {
    let usage: PlanUsage?
    let showsEmpty: Bool
    /// Whose limits: named in the tooltip and to VoiceOver.
    let agent: Agent
    /// Several agents on: a dot in the agent's colour before the ring.
    let marked: Bool

    public init(usage: PlanUsage?, showsEmpty: Bool = false, agent: Agent = .claude, marked: Bool = false) {
        self.usage = usage
        self.showsEmpty = showsEmpty
        self.agent = agent
        self.marked = marked
    }

    public var body: some View {
        // Refresh now and then so a passed reset drops back to 0%.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let (kind, w) = usage?.current(now: context.date).compactWindow {
                let color = PlanUsageStyle.color(w.usedPercent)
                HStack(spacing: 4) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.2), lineWidth: 2.2)
                        Circle()
                            .trim(from: 0, to: min(1, max(0.03, w.usedPercent / 100)))
                            .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        // Whose ring: inside it, apart from a session's state dot beside it.
                        if marked { AgentDot(agent: agent, size: 4) }
                    }
                    .frame(width: 11, height: 11)
                    // Used up: when it comes back matters more than "100%".
                    Text(w.usedPercent >= 100 && w.resetsAt != nil
                         ? PlanUsage.shortCountdown(to: w.resetsAt!, from: context.date)
                         : "\(Int(w.usedPercent.rounded()))%")
                        .font(.system(size: MelyType.footnote, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(color)
                }
                .layoutProbe("plan.gauge")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.label(kind, w, agent: agent, now: context.date))
                .help(Self.label(kind, w, agent: agent, now: context.date))
            } else if showsEmpty {
                HStack(spacing: 4) {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 2.2).frame(width: 11, height: 11)
                        .overlay { if marked { AgentDot(agent: agent, size: 4) } }
                    Text("—")
                        .font(.system(size: MelyType.footnote, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(MelyInk.tertiary))
                }
                .layoutProbe("plan.gauge")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Лимиты \(agent.shortName): нет данных")
                .help("Лимиты \(agent.shortName): нет данных")
            }
        }
    }

    static func label(_ kind: PlanUsage.Kind, _ w: PlanWindow, agent: Agent = .claude, now: Date) -> String {
        let reset = w.resetsAt.map { ", сброс через \(PlanUsage.countdown(to: $0, from: now))" } ?? ""
        if w.usedPercent >= 100 { return "Лимит \(agent.shortName) \(kind.span) исчерпан\(reset)" }
        return "Лимит \(agent.shortName) \(kind.span): \(Int(w.usedPercent.rounded())) процентов\(reset)"
    }
}

/// Both windows spelled out: which limit, how full, when it resets (the header pill's card).
public struct PlanUsageCard: View {
    let usage: PlanUsage?
    let agent: Agent
    let problem: String?

    public init(usage: PlanUsage?, agent: Agent = .claude, problem: String? = nil) {
        self.usage = usage
        self.agent = agent
        self.problem = problem
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            PlanUsageBlock(usage: usage, agent: agent, problem: problem, now: context.date)
                .padding(12)
                .frame(width: 250, alignment: .leading)
                .usageCardChrome()
        }
    }
}

/// The card with every agent on: a block each; a click on one pins it in the notch.
public struct AgentsUsageCard: View {
    let agents: AgentsModel

    public init(agents: AgentsModel) {
        self.agents = agents
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 8) {
                ForEach(agents.enabled, id: \.self) { agent in
                    block(agent, now: context.date)
                }
                Text("Закреплён в челке — нажми на другого, чтобы сменить")
                    .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
            .padding(10)
            .frame(width: 300, alignment: .leading)
            .usageCardChrome()
        }
    }

    private func block(_ agent: Agent, now: Date) -> some View {
        let store = agents.usage(agent)
        let pinned = agents.shownAgent == agent
        return Button {
            MelyHaptics.tap()
            agents.pinned = agent
        } label: {
            PlanUsageBlock(usage: store?.usage, agent: agent, problem: store?.problem, now: now, pinned: pinned, marked: true,
                           compact: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(pinned ? MelyFill.raised : MelyFill.card), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: MelyRadius.medium)
                    .strokeBorder(pinned ? AgentStyle.color(agent).opacity(0.8) : .clear, lineWidth: 1.5))
                .contentShape(RoundedRectangle(cornerRadius: MelyRadius.medium))
        }
        .buttonStyle(.plain)
        .accessibilityHint(pinned ? "Закреплён в челке" : "Закрепить в челке")
        .layoutProbe("plan.card.\(agent.rawValue)", inside: "plan.card")
    }
}

/// One agent's limits: the title, both windows, the age; Codex's free resets.
struct PlanUsageBlock: View {
    let usage: PlanUsage?
    let agent: Agent
    let problem: String?
    let now: Date
    var pinned = false
    /// Several agents: the agent's dot before its name.
    var marked = false
    /// A block among several: each window on one line, so the card fits under the notch.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 9) {
            HStack(spacing: 6) {
                if marked { AgentDot(agent: agent) }
                Text("Лимиты \(agent.shortName)").font(.system(size: MelyType.footnote, weight: .semibold)).foregroundStyle(.white.opacity(MelyInk.secondary))
                if let plan = usage?.plan, !plan.isEmpty {
                    Text(plan.capitalized).font(.system(size: MelyType.caption, weight: .medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.white.opacity(MelyFill.raised), in: Capsule())
                        .foregroundStyle(.white.opacity(MelyInk.strong))
                }
                Spacer(minLength: 0)
                if pinned {
                    Image(systemName: "pin.fill").font(.system(size: MelyType.caption, weight: .semibold))
                        .foregroundStyle(AgentStyle.color(agent))
                        .accessibilityHidden(true)
                }
            }
            if let usage = usage?.current(now: now), usage.fiveHour != nil || usage.sevenDay != nil {
                if compact {
                    if let w = usage.fiveHour { line("5 ч", w) }
                    if let w = usage.sevenDay { line("Неделя", w) }
                } else {
                    if let w = usage.fiveHour { row("5 часов", w) }
                    if let w = usage.sevenDay { row("Неделя", w) }
                }
                if let credits = usage.resetCredits, credits > 0 {
                    Text("Бесплатных сбросов: \(credits)")
                        .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.secondary))
                }
                if usage.isStale(now: now) {
                    Text(usage.ageText(now: now))
                        .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                }
            } else {
                Text(problem ?? (agent == .claude ? "Нет данных: появятся с первым ответом Claude Code" : "Нет данных"))
                    .font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
    }

    /// «Неделя ▓▓▓░ 86% · 3 дн 4 ч».
    private func line(_ title: String, _ w: PlanWindow) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: MelyType.footnote, weight: .medium))
                .frame(width: 46, alignment: .leading)
            Capsule().fill(.white.opacity(MelyFill.raised)).frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(PlanUsageStyle.color(w.usedPercent))
                            .frame(width: g.size.width * min(1, max(0.03, w.usedPercent / 100)))
                    }
                }
            Text("\(Int(w.usedPercent.rounded()))%")
                .font(.system(size: MelyType.footnote, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(w.isWarning ? PlanUsageStyle.color(w.usedPercent) : .white)
                .frame(width: 34, alignment: .trailing)
            Text(w.resetsAt.map { PlanUsage.countdown(to: $0, from: now) } ?? "")
                .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.secondary))
                .lineLimit(1).fixedSize()
                .frame(minWidth: 62, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Лимит \(agent.shortName) \(title): \(Int(w.usedPercent.rounded())) процентов")
    }

    private func row(_ title: String, _ w: PlanWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: MelyType.body, weight: .medium))
                Spacer()
                Text("\(Int(w.usedPercent.rounded()))%")
                    .font(.system(size: MelyType.body, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(w.isWarning ? PlanUsageStyle.color(w.usedPercent) : .white)
            }
            Capsule().fill(.white.opacity(MelyFill.raised)).frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(PlanUsageStyle.color(w.usedPercent))
                            .frame(width: g.size.width * min(1, max(0.03, w.usedPercent / 100)))
                    }
                }
            if let reset = w.resetsAt {
                Text("сброс через \(PlanUsage.countdown(to: reset, from: now))")
                    .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.secondary))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// The dark card under the header's ring.
    func usageCardChrome() -> some View {
        background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: MelyRadius.large))
            .overlay(RoundedRectangle(cornerRadius: MelyRadius.large).stroke(.white.opacity(MelyFill.raised)))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    }
}
