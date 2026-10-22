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

    public init(usage: PlanUsage?) {
        self.usage = usage
    }

    public var body: some View {
        // Countdowns move; a minute is precise enough.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let usage = usage?.current(now: context.date) {
                HStack(spacing: 12) {
                    if let w = usage.fiveHour { window("5 ч", w, now: context.date).fixedSize() }
                    if let w = usage.sevenDay { window("Неделя", w, now: context.date).fixedSize() }
                    // Old values are shown with their age, not as live. One line: wrapped, it
                    // would break the bar under the sessions (no agent, no fresh numbers).
                    if context.date.timeIntervalSince(usage.updatedAt) > 15 * 60 {
                        Text("обновлено \(PlanUsage.countdown(to: context.date, from: usage.updatedAt)) назад")
                            .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(-1)
                    }
                }
                .layoutProbe("plan.overview", inside: "sessions.usage")
            } else {
                Text("Лимиты: нет данных").font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.tertiary))
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

    public init(usage: PlanUsage?, showsEmpty: Bool = false) {
        self.usage = usage
        self.showsEmpty = showsEmpty
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
                .accessibilityLabel(Self.label(kind, w, now: context.date))
                .help(Self.label(kind, w, now: context.date))
            } else if showsEmpty {
                HStack(spacing: 4) {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 2.2).frame(width: 11, height: 11)
                    Text("—")
                        .font(.system(size: MelyType.footnote, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(MelyInk.tertiary))
                }
                .layoutProbe("plan.gauge")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Лимиты Claude: нет данных")
                .help("Лимиты Claude: нет данных")
            }
        }
    }

    static func label(_ kind: PlanUsage.Kind, _ w: PlanWindow, now: Date) -> String {
        let reset = w.resetsAt.map { ", сброс через \(PlanUsage.countdown(to: $0, from: now))" } ?? ""
        if w.usedPercent >= 100 { return "Лимит Claude \(kind.span) исчерпан\(reset)" }
        return "Лимит Claude \(kind.span): \(Int(w.usedPercent.rounded())) процентов\(reset)"
    }
}

/// Both windows spelled out: which limit, how full, when it resets (the header pill's card).
public struct PlanUsageCard: View {
    let usage: PlanUsage?

    public init(usage: PlanUsage?) {
        self.usage = usage
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 9) {
                Text("Лимиты Claude").font(.system(size: MelyType.footnote, weight: .semibold)).foregroundStyle(.white.opacity(MelyInk.secondary))
                if let usage = usage?.current(now: context.date), usage.fiveHour != nil || usage.sevenDay != nil {
                    if let w = usage.fiveHour { row("5 часов", w, now: context.date) }
                    if let w = usage.sevenDay { row("Неделя", w, now: context.date) }
                    if context.date.timeIntervalSince(usage.updatedAt) > 15 * 60 {
                        Text("обновлено \(PlanUsage.countdown(to: context.date, from: usage.updatedAt)) назад")
                            .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                    }
                } else {
                    Text("Нет данных: появятся с первым ответом Claude Code")
                        .font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.secondary))
                }
            }
            .padding(12)
            .frame(width: 250, alignment: .leading)
            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: MelyRadius.large))
            .overlay(RoundedRectangle(cornerRadius: MelyRadius.large).stroke(.white.opacity(MelyFill.raised)))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
        }
    }

    private func row(_ title: String, _ w: PlanWindow, now: Date) -> some View {
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
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}
