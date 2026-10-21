import SwiftUI
import MelyCore

/// The request at the head of the queue, with "1 из 3" when more wait.
public struct RequestCard: View {
    let request: PendingRequest
    let position: Int
    let total: Int
    let decide: (HookDecision) -> Void
    /// "Ответить в терминале": Claude Code asks there; the host comes forward.
    let answerInTerminal: () -> Void

    public init(request: PendingRequest, position: Int, total: Int,
                decide: @escaping (HookDecision) -> Void, answerInTerminal: @escaping () -> Void) {
        self.request = request
        self.position = position
        self.total = total
        self.decide = decide
        self.answerInTerminal = answerInTerminal
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(SessionStateStyle.color(request.isQuestion ? .waitingAnswer : .waitingApproval)).frame(width: 7, height: 7)
                Text(request.isQuestion ? "Вопрос" : "Разрешение").font(.system(size: MelyType.body, weight: .semibold))
                Text("\(request.projectName) · \(request.hostName)")
                    .font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.secondary)).lineLimit(1)
                Spacer(minLength: 6)
                if total > 1 {
                    Text("\(position) из \(total)").font(.system(size: MelyType.footnote, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.white.opacity(MelyFill.raised), in: Capsule())
                }
            }
            switch request.kind {
            case .approval(_, let title, let detail, let canAlways):
                ApprovalBody(title: title, detail: detail, canAlways: canAlways,
                             decide: decide, answerInTerminal: answerInTerminal)
            case .question(let payload):
                QuestionBody(payload: payload, decide: decide, answerInTerminal: answerInTerminal)
                    .id(request.id)  // fresh selection for every question card
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(MelyFill.raised), in: RoundedRectangle(cornerRadius: MelyRadius.large))
        .overlay(RoundedRectangle(cornerRadius: MelyRadius.large).strokeBorder(SessionStateStyle.color(request.isQuestion ? .waitingAnswer : .waitingApproval).opacity(0.5)))
    }
}

private struct ApprovalBody: View {
    let title: String
    let detail: String?
    let canAlways: Bool
    let decide: (HookDecision) -> Void
    let answerInTerminal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // "Тестирует · npm test": the command itself is shown in full below.
            Text(detail == nil ? title : title.components(separatedBy: " · ")[0])
                .font(.system(size: MelyType.title, weight: .semibold)).lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: MelyType.footnote, design: .monospaced))
                    .foregroundStyle(.white.opacity(MelyInk.primary))
                    .lineLimit(6)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                CardButton("Разрешить", prominent: true) { decide(.allow) }
                if canAlways { CardButton("Всегда") { decide(.always) } }
                CardButton("Отклонить", destructive: true) { decide(.deny) }
                Spacer(minLength: 4)
                CardButton("В терминале", subtle: true, action: answerInTerminal)
                    .help("Ответить в терминале")
            }
        }
    }
}

private struct QuestionBody: View {
    let payload: QuestionPayload
    let decide: (HookDecision) -> Void
    let answerInTerminal: () -> Void
    /// Chosen labels per question index.
    @State private var chosen: [Int: Set<String>] = [:]
    @State private var custom: [Int: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(payload.questions.enumerated()), id: \.offset) { index, question in
                        questionView(index, question)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            // More options below: they fade out at the edge instead of being cut.
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.85),
                                         .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            HStack(spacing: 6) {
                if !payload.answersWithOneClick || !(custom[0] ?? "").isEmpty {
                    CardButton("Отправить", prominent: true, action: send).disabled(!isComplete)
                }
                Spacer(minLength: 4)
                CardButton("В терминале", subtle: true, action: answerInTerminal)
            }
        }
    }

    @ViewBuilder private func questionView(_ index: Int, _ q: QuestionPayload.Question) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let header = q.header {
                    Text(header).font(.system(size: MelyType.caption, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.white.opacity(MelyFill.selected), in: Capsule())
                }
                if q.multiSelect {
                    Text("несколько вариантов").font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.secondary))
                }
            }
            Text(q.text).font(.system(size: MelyType.title, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            ForEach(q.options, id: \.label) { option in
                optionRow(index, q, option)
            }
            TextField("Свой вариант", text: Binding(get: { custom[index] ?? "" }, set: { custom[index] = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: MelyType.body))
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(.white.opacity(MelyFill.raised), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
                .onSubmit { if isComplete { send() } }
        }
    }

    private func optionRow(_ index: Int, _ q: QuestionPayload.Question, _ option: QuestionPayload.Option) -> some View {
        let isOn = chosen[index, default: []].contains(option.label)
        return Button {
            if q.multiSelect {
                chosen[index, default: []].formSymmetricDifference([option.label])
            } else {
                chosen[index] = [option.label]
                custom[index] = nil
                if payload.answersWithOneClick { send() }
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: q.multiSelect ? (isOn ? "checkmark.square.fill" : "square")
                                                : (isOn ? "largecircle.fill.circle" : "circle"))
                    .font(.system(size: MelyType.body))
                    .foregroundStyle(isOn ? SessionStateStyle.color(.waitingAnswer) : .white.opacity(MelyInk.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label).font(.system(size: MelyType.body, weight: .medium))
                    if let description = option.description {
                        Text(description).font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.white.opacity(isOn ? 0.14 : 0.05), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func answer(_ index: Int) -> HookDecision.AnswerValue? {
        let q = payload.questions[index]
        let text = (custom[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if q.multiSelect {
            // Keep the option order, then the user's own variant.
            var labels = q.options.map(\.label).filter { chosen[index, default: []].contains($0) }
            if !text.isEmpty { labels.append(text) }
            return labels.isEmpty ? nil : .multiple(labels)
        }
        if !text.isEmpty { return .single(text) }
        return chosen[index]?.first.map { .single($0) }
    }

    private var isComplete: Bool { payload.questions.indices.allSatisfy { answer($0) != nil } }

    private func send() {
        var answers: [String: HookDecision.AnswerValue] = [:]
        for (i, q) in payload.questions.enumerated() {
            guard let a = answer(i) else { return }
            answers[q.text] = a
        }
        decide(.answer(answers))
    }
}

private struct CardButton: View {
    let title: String
    var prominent = false
    var destructive = false
    var subtle = false
    let action: () -> Void

    init(_ title: String, prominent: Bool = false, destructive: Bool = false, subtle: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.destructive = destructive
        self.subtle = subtle
        self.action = action
    }

    var body: some View {
        Button(action: { MelyHaptics.tap(); action() }) {
            Text(title)
                .font(.system(size: MelyType.footnote, weight: .semibold))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .foregroundStyle(prominent ? .black : destructive ? Color(red: 1.0, green: 0.5, blue: 0.47)
                                 : .white.opacity(subtle ? 0.6 : 1))
                .background(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(subtle ? 0 : 0.14)),
                            in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Which page the expanded island shows. The app switches it (hotkey, a dropped file).
@MainActor
@Observable
public final class IslandTabs {
    public enum Tab: Hashable, Sendable { case sessions, chat, messages, today, music }
    public var selected: Tab = .sessions
    /// Bumped to put the cursor in the chat field.
    public var chatFocus = 0

    public init() {}

    public func showChat() {
        selected = .chat
        chatFocus += 1
    }
}

/// Expanded island: a waiting request takes all of it; otherwise the sessions and,
/// when the chat is on, a tab for it.
public struct ClaudeOverview: View {
    let store: SessionStore
    let queue: ApprovalQueue
    let usage: PlanUsageStore?
    let tabs: IslandTabs?
    let chat: AnyView?
    /// The mirrored notifications tab, with its unseen count.
    let messages: AnyView?
    let messagesBadge: Int
    /// The calendar's "Сегодня" tab.
    let today: AnyView?
    /// The mini-player, while something plays (and 5 minutes after).
    let music: AnyView?
    let open: (ClaudeSession) -> Void
    let decide: (PendingRequest, HookDecision) -> Void
    let answerInTerminal: (PendingRequest) -> Void
    /// What each page measured itself at (`islandPart`).
    @State private var heights: [IslandTabs.Tab: CGFloat] = [:]

    public init(store: SessionStore, queue: ApprovalQueue, usage: PlanUsageStore? = nil,
                tabs: IslandTabs? = nil, chat: AnyView? = nil, messages: AnyView? = nil, messagesBadge: Int = 0,
                today: AnyView? = nil, music: AnyView? = nil,
                open: @escaping (ClaudeSession) -> Void,
                decide: @escaping (PendingRequest, HookDecision) -> Void,
                answerInTerminal: @escaping (PendingRequest) -> Void) {
        self.store = store
        self.queue = queue
        self.usage = usage
        self.tabs = tabs
        self.chat = chat
        self.messages = messages
        self.messagesBadge = messagesBadge
        self.today = today
        self.music = music
        self.open = open
        self.decide = decide
        self.answerInTerminal = answerInTerminal
    }

    public var body: some View {
        Group {
            if let request = queue.current {
                RequestCard(request: request, position: 1, total: queue.requests.count,
                            decide: { decide(request, $0) }, answerInTerminal: { answerInTerminal(request) })
                    .transition(.opacity)
            } else if let tabs {
                let tab = tabs.selected
                // The sections are chosen in the header, level with the notch (task 7.9).
                Group {
                    if tabs.selected == .chat, let chat {
                        chat
                    } else if tabs.selected == .messages, let messages {
                        messages
                    } else if tabs.selected == .today, let today {
                        today
                    } else if tabs.selected == .music, let music {
                        music
                    } else {
                        SessionsOverview(store: store, usage: usage, showsHeader: false, open: open)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Each page measures itself: the leaving one keeps its own number.
                .onPreferenceChange(IslandPartHeightKey.self) { height in
                    MainActor.assumeIsolated { heights[tab] = height }
                }
                .transformPreference(IslandPartHeightKey.self) { $0 = 0 }
                // A new section slides in a little as it fades (task 7.3).
                .id(tabs.selected)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
            } else {
                SessionsOverview(store: store, usage: usage, open: open)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: queue.current?.id)
        .animation(MelyMotion.tab, value: tabs?.selected)
        .preference(key: IslandContentHeightKey.self, value: pageHeight)
    }

    /// The chat and a request get `IslandPresentation.fullPage`; the other pages what they
    /// measured (the sessions: room for three or four, `SessionsOverview.listHeight`).
    private var pageHeight: CGFloat? {
        guard queue.current == nil, let tabs else { return IslandPresentation.fullPage }
        if tabs.selected == .chat, chat != nil { return IslandPresentation.fullPage }
        return heights[tabs.selected]
    }
}

