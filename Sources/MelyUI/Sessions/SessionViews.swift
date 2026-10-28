import SwiftUI
import AppKit
import MelyCore

/// Colour and words for a session state.
enum SessionStateStyle {
    static func color(_ state: SessionState) -> Color {
        switch state {
        case .idle: Color(white: 0.55)
        case .thinking, .working: MelyTint.working
        case .waitingApproval: MelyTint.approval
        case .waitingAnswer: MelyTint.question
        case .finished: MelyTint.done
        case .error: MelyTint.error
        case .rateLimited: MelyTint.limit
        }
    }

    static func title(_ state: SessionState) -> String {
        switch state {
        case .idle: "Ожидает"
        case .thinking: "Думает"
        case .working: "Работает"
        case .waitingApproval: "Нужно разрешение"
        case .waitingAnswer: "Нужен ответ"
        case .finished: "Готово"
        case .error: "Ошибка"
        case .rateLimited: "Лимит"
        }
    }
}

/// Icon of the app hosting a session.
struct HostIcon: View {
    let bundleId: String?
    var size: CGFloat = 22

    var body: some View {
        if let bundleId, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "terminal")
                .font(.system(size: size * 0.64, weight: .medium))
                .frame(width: size, height: size)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

public struct DiffCounts: View {
    let added: Int
    let removed: Int

    public init(added: Int, removed: Int) {
        self.added = added
        self.removed = removed
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text("+\(added)").foregroundStyle(Color(red: 0.35, green: 0.85, blue: 0.5))
            Text("−\(removed)").foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.42))
        }
        .font(.system(size: MelyType.footnote, weight: .semibold, design: .monospaced))
    }
}

public struct SessionRow: View {
    let session: ClaudeSession
    let open: () -> Void
    /// Claude's last message unfolded in full.
    @State private var expanded: Bool

    public init(session: ClaudeSession, expanded: Bool = false, open: @escaping () -> Void) {
        self.session = session
        self.open = open
        _expanded = State(initialValue: expanded)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // The session's own little Mely, its host app as a badge.
                SessionMely(session: session, size: 28)
                    .overlay(alignment: .bottomTrailing) {
                        HostIcon(bundleId: session.host.bundleId, size: 13).offset(x: 4, y: 3)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        // One line whatever the name: the row never grows (task 7.10).
                        Text(session.projectName).font(.system(size: MelyType.title, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                        Text(session.host.name).font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.secondary))
                            .lineLimit(1).fixedSize()
                        if session.subagents > 0 {
                            Text("+\(session.subagents) агент").font(.system(size: MelyType.caption, weight: .medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.white.opacity(MelyFill.raised), in: Capsule())
                        }
                    }
                    if let message = shownMessage, !expanded {
                        // Claude's answer, not just "Готово": two lines, the rest a click away. A
                        // question is what matters, and it comes last: then the last paragraph.
                        Text(Self.inline(session.asksBack ? Self.lastParagraph(message) : message))
                            .font(.system(size: MelyType.footnote))
                            .foregroundStyle(.white.opacity(MelyInk.strong))
                            .lineLimit(2)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(MelyMotion.tab) { expanded = true } }
                            .help("Показать ответ целиком")
                    } else {
                        Text(detail)
                            .font(.system(size: MelyType.footnote))
                            .foregroundStyle(.white.opacity(MelyInk.strong))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                if !session.diffs.isEmpty {
                    DiffCounts(added: session.addedLines, removed: session.removedLines)
                }
                HStack(spacing: 5) {
                    Circle().fill(stateColor).frame(width: 7, height: 7)
                    Text(stateTitle).font(.system(size: MelyType.footnote, weight: .medium)).fixedSize()
                }
                .foregroundStyle(.white.opacity(MelyInk.primary))
                if shownMessage != nil {
                    Button { withAnimation(MelyMotion.tab) { expanded.toggle() } } label: {
                        Image(systemName: "chevron.down").font(.system(size: MelyType.caption, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .foregroundStyle(.white.opacity(MelyInk.secondary))
                            .frame(width: 18, height: 18).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(expanded ? "Свернуть ответ" : "Показать ответ целиком")
                    .layoutProbe("session.expand.\(session.id)", inside: "session.row.\(session.id)")
                }
                Button("Открыть", action: open)
                    .buttonStyle(.plain)
                    .font(.system(size: MelyType.footnote, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(MelyFill.selected), in: Capsule())
                    .fixedSize()
                    .accessibilityLabel("Открыть \(session.projectName) в \(session.host.name)")
                    .layoutProbe("session.open.\(session.id)", inside: "session.row.\(session.id)")
            }
            if expanded, let message = shownMessage {
                ScrollViewReader { scroll in
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(Self.inline(message))
                            .font(.system(size: MelyType.footnote))
                            .foregroundStyle(.white.opacity(MelyInk.primary))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Color.clear.frame(height: 1).id("end")
                    }
                    // A question waits at the end: open there.
                    .onAppear { if session.asksBack { scroll.scrollTo("end", anchor: .bottom) } }
                }
                .frame(maxHeight: 140)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.white.opacity(MelyFill.card), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
                .layoutProbe("session.message.\(session.id)", inside: "session.row.\(session.id)")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.white.opacity(MelyFill.card), in: RoundedRectangle(cornerRadius: MelyRadius.large))
        .layoutProbe("session.row.\(session.id)", inside: "sessions.list")
    }

    /// Claude's last message, once the turn is over (while it works, the current step).
    private var shownMessage: String? {
        switch session.state {
        case .idle, .finished: session.lastMessage
        default: nil
        }
    }

    private var stateTitle: String { session.asksBack ? "Ждёт ответа" : SessionStateStyle.title(session.state) }
    private var stateColor: Color { session.asksBack ? MelyTint.question : SessionStateStyle.color(session.state) }

    /// The last paragraph of a message: where Claude puts its question.
    static func lastParagraph(_ message: String) -> String {
        message.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty } ?? message
    }

    /// Bold, code and links of a Markdown answer; the text as is when it does not parse.
    static func inline(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }

    private var detail: String {
        if case .finished(let summary) = session.state, !summary.isEmpty { return summary }
        if case .error(let message) = session.state { return message }
        return session.step ?? "—"
    }
}

/// Expanded island: every live session.
public struct SessionsOverview: View {
    let store: SessionStore
    let usage: PlanUsageStore?
    /// Off when the island's tab bar already shows the title and the gauge.
    let showsHeader: Bool
    let open: (ClaudeSession) -> Void

    public init(store: SessionStore, usage: PlanUsageStore? = nil, showsHeader: Bool = true,
                open: @escaping (ClaudeSession) -> Void) {
        self.store = store
        self.usage = usage
        self.showsHeader = showsHeader
        self.open = open
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                HStack {
                    Text("Claude Code").font(.system(size: MelyType.body, weight: .semibold)).foregroundStyle(.white.opacity(MelyInk.secondary))
                    Spacer(minLength: 8)
                    if let usage { PlanUsageGauge(usage: usage.usage) }
                }
            }
            if store.sessions.isEmpty {
                Text("Нет активных сессий").font(.system(size: MelyType.title)).foregroundStyle(.white.opacity(MelyInk.secondary))
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 20)
                    .layoutProbe("sessions.empty", inside: "content")
                    .islandPart()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.sessions) { session in
                            SessionRow(session: session) { open(session) }
                        }
                    }
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: IslandPartHeightKey.self,
                                               value: Self.listHeight(rows: geo.size.height, count: store.sessions.count))
                    })
                }
                .layoutProbe("sessions.list", inside: "content", scrolls: true)
            }
            // The header only has room for a ring: here, which limit, how much and when.
            if !showsHeader, let usage {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Text("Лимиты").font(.system(size: MelyType.footnote, weight: .medium)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                    PlanUsageGauge(usage: usage.usage)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(.white.opacity(MelyFill.card), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
                .layoutProbe("sessions.usage", inside: "content")
                // The stack's spacing twice: before the spacer and after it.
                .islandPart(spacing: 16)
            }
        }
    }
}

extension SessionsOverview {
    /// The list's room in the open island: three rows for up to three sessions (the island
    /// does not jump with each one), four for four, and past that four and a sliver of the
    /// fifth, so it shows the rest scrolls.
    static func listHeight(rows height: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return height }
        let spacing: CGFloat = 6
        let row = (height + spacing) / CGFloat(count)
        let shown: CGFloat = count <= 3 ? 3 : count == 4 ? 4 : 4.4
        return row * shown - spacing
    }
}

/// Right side of the compact island: the session that matters most.
public struct CompactSessionStatus: View {
    let store: SessionStore
    let usage: PlanUsageStore?
    let music: NowPlayingModel?

    public init(store: SessionStore, usage: PlanUsageStore? = nil, music: NowPlayingModel? = nil) {
        self.store = store
        self.usage = usage
        self.music = music
    }

    public var body: some View {
        HStack(spacing: 6) {
            sessionStatus
            if music?.current?.isPlaying == true { EqualizerBars().frame(width: 11, height: 11) }
            CompactPlanGauge(usage: usage?.usage)
        }
    }

    @ViewBuilder private var sessionStatus: some View {
        if let s = Self.focus(store.sessions) {
            HStack(spacing: 5) {
                Circle().fill(SessionStateStyle.color(s.state)).frame(width: 6, height: 6)
                // The side is narrow: the plan gauge takes the place of the text.
                if usage?.usage != nil {
                    EmptyView()
                } else if !s.diffs.isEmpty, s.state == .working || s.state == .thinking {
                    DiffCounts(added: s.addedLines, removed: s.removedLines)
                } else {
                    Text(s.projectName).font(.system(size: MelyType.footnote, weight: .semibold)).lineLimit(1)
                }
            }
            .foregroundStyle(.white)
        }
    }

    /// Waiting for the user beats working beats the rest; newest activity first.
    static func focus(_ sessions: [ClaudeSession]) -> ClaudeSession? {
        func rank(_ s: SessionState) -> Int {
            switch s {
            case .waitingApproval, .waitingAnswer: 0
            case .error, .rateLimited: 1
            case .working, .thinking: 2
            case .finished: 3
            case .idle: 4
            }
        }
        return sessions.min { a, b in
            rank(a.state) != rank(b.state) ? rank(a.state) < rank(b.state) : a.lastSeen > b.lastSeen
        }
    }
}
