import SwiftUI
import MelyCore

/// Chat with Claude in the expanded island: the window it was
/// opened from as a chip, bubbles, the model on a pill over the field, dictation.
public struct ChatView: View {
    let conversation: ChatConversation
    let preferences: ChatPreferences?
    let tabs: IslandTabs?
    let openSettings: () -> Void
    /// Continues the conversation in the Claude desktop app; nil when it is not installed.
    let openInClaude: (() -> Void)?
    @State private var draft = ""
    @State private var showModels = false
    @State private var dictation = ChatDictation()
    /// Messages have scrolled up past the top edge: it fades.
    @State private var scrolledDown = false
    /// The messages are scrolled to their end and stay there as they grow.
    @State private var following = true
    @FocusState private var fieldFocused: Bool

    public init(conversation: ChatConversation, preferences: ChatPreferences? = nil, tabs: IslandTabs? = nil,
                openSettings: @escaping () -> Void, openInClaude: (() -> Void)? = nil) {
        self.conversation = conversation
        self.preferences = preferences
        self.tabs = tabs
        self.openSettings = openSettings
        self.openInClaude = openInClaude
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let context = conversation.context {
                ContextChip(context: context, dismiss: conversation.dismissContext)
                    .layoutProbe("chat.context", inside: "content")
            }
            if conversation.messages.isEmpty {
                placeholder.layoutProbe("chat.placeholder", inside: "content").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                messages
            }
            if let hint = conversation.setupHint {
                setup(hint)
            } else {
                footer
                input
            }
        }
        .foregroundStyle(.white)
        .onAppear { fieldFocused = true }
        .onChange(of: tabs?.chatFocus) { fieldFocused = true }
        .onChange(of: dictation.text) { if dictation.isRecording { draft = dictation.text } }
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Text("Спросите Claude о чём угодно").font(.system(size: MelyType.title)).foregroundStyle(.white.opacity(MelyInk.secondary))
            Text("⌃⌥Пробел — открыть чат · файл можно перетащить на челку · ⌘N — новый разговор")
                .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(conversation.messages.enumerated()), id: \.element.id) { index, message in
                        ChatBubble(message: message).id(message.id)
                            .layoutProbe("chat.message.\(index)", inside: "chat.viewport")
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.vertical, 6)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .frame(maxHeight: .infinity)
            .layoutProbe("chat.viewport", inside: "content", scrolls: true)
            // An answer that grows (streaming, then redrawn as Markdown) stays in sight to its
            // last line, unless the reader has scrolled up to read something else.
            .onScrollGeometryChange(for: ChatScroll.self) { ChatScroll($0) } action: { old, new in
                scrolledDown = new.fromTop > 1
                if new.size != old.size {
                    // A size changes in several steps: whether to follow was decided before.
                    if following { proxy.scrollTo("end", anchor: .bottom) }
                } else {
                    following = new.toBottom <= ChatScroll.followDistance
                }
            }
            // What scrolls away fades out under the top edge instead of being cut; at the top
            // nothing is faded.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: scrolledDown ? ChatScroll.fade : 0)
                    Color.black
                }
            }
            .overlay(alignment: .top) {
                if scrolledDown { Color.clear.frame(height: ChatScroll.fade).layoutProbe("chat.fade") }
            }
            .onChange(of: conversation.messages.count) {
                // A new question: back to the end, whatever was being read. Not animated: the
                // offsets in between would read as the reader scrolling away.
                following = true
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
    }

    /// A new conversation and the attachments on the left, the model pill on the right.
    private var footer: some View {
        HStack(spacing: 6) {
            if !conversation.messages.isEmpty {
                Button(action: newConversation) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil").font(.system(size: MelyType.micro, weight: .semibold))
                        Text("Новый разговор").font(.system(size: MelyType.caption, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(MelyInk.secondary))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(MelyFill.card), in: Capsule())
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .help("Начать заново: Claude забудет этот разговор (⌘N)")
                .layoutProbe("chat.new", row: "chat.footer", inside: "content")
            }
            ForEach(conversation.pending) { file in
                HStack(spacing: 4) {
                    Image(systemName: icon(file.kind)).font(.system(size: MelyType.caption))
                    Text(file.name).font(.system(size: MelyType.footnote)).lineLimit(1).truncationMode(.middle)
                    Button { conversation.removeAttachment(file.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Убрать \(file.name)")
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.white.opacity(MelyFill.raised), in: Capsule())
                .frame(maxWidth: 170)
                .layoutProbe("chat.attachment.\(file.id)", row: "chat.footer", inside: "content")
            }
            if let error = conversation.attachmentError ?? dictation.error {
                Text(error).font(.system(size: MelyType.caption)).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5)).lineLimit(1)
                    .layoutProbe("chat.error", row: "chat.footer", inside: "content")
            }
            Spacer(minLength: 6)
            if let openInClaude, !conversation.messages.isEmpty, !conversation.isStreaming {
                Button(action: openInClaude) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app").font(.system(size: MelyType.micro, weight: .semibold))
                        Text("Открыть в Claude").font(.system(size: MelyType.caption, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(MelyInk.secondary))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(MelyFill.card), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Новый чат в приложении Claude с этим разговором")
                .layoutProbe("chat.openInClaude", row: "chat.footer", inside: "content")
            }
            if let preferences {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showModels.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(ChatStyle.routeColor(preferences.route)).frame(width: 6, height: 6)
                        Text(preferences.model.title).font(.system(size: MelyType.caption, weight: .medium))
                            .foregroundStyle(.white.opacity(MelyInk.secondary))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                            .foregroundStyle(.white.opacity(MelyInk.tertiary))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(MelyFill.card), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(preferences.route.caption)
                .accessibilityLabel("Модель: \(preferences.model.title), \(preferences.route.caption)")
                .layoutProbe("chat.model", row: "chat.footer", inside: "content")
                .popover(isPresented: $showModels, arrowEdge: .bottom) {
                    ChatModelPicker(preferences: preferences, openSettings: openSettings) { showModels = false }
                        .frame(width: 300)
                }
            }
        }
    }

    private var input: some View {
        HStack(spacing: 8) {
            TextField(conversation.messages.isEmpty ? "Спросите что угодно…" : "Продолжить…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: MelyType.title))
                .focused($fieldFocused)
                .onSubmit(send)
            Button {
                Task {
                    if dictation.isRecording { draft = await dictation.finish() }
                    else { await dictation.start(from: draft) }
                }
            } label: {
                Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: MelyType.footnote, weight: .semibold))
                    .foregroundStyle(dictation.isRecording ? Color(red: 0.96, green: 0.31, blue: 0.37) : .white.opacity(MelyInk.secondary))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(dictation.isRecording ? "Остановить диктовку" : "Диктовать")
            if conversation.isStreaming {
                Button(action: conversation.cancel) {
                    Image(systemName: "stop.fill").font(.system(size: MelyType.micro, weight: .bold)).foregroundStyle(.black)
                }
                .buttonStyle(SendButtonStyle())
                .accessibilityLabel("Остановить ответ")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: MelyType.footnote, weight: .semibold)).foregroundStyle(.black)
                }
                .buttonStyle(SendButtonStyle())
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && conversation.pending.isEmpty)
                .accessibilityLabel("Отправить")
            }
            // ⌘N: a new conversation.
            Button("", action: newConversation)
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.white.opacity(MelyFill.card), in: RoundedRectangle(cornerRadius: MelyRadius.large))
        .simultaneousGesture(TapGesture().onEnded { fieldFocused = true })
        .layoutProbe("chat.input", inside: "content")
    }

    private func setup(_ hint: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape.fill").foregroundStyle(.white.opacity(MelyInk.secondary))
            Text(hint).font(.system(size: MelyType.body)).foregroundStyle(.white.opacity(MelyInk.strong))
                .fixedSize(horizontal: false, vertical: true)
                .layoutProbe("chat.setup.hint", inside: "chat.setup", checksText: true)
            Spacer(minLength: 4)
            Button("Настройки чата…", action: openSettings)
                .buttonStyle(.plain)
                .font(.system(size: MelyType.footnote, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.white.opacity(MelyFill.selected), in: Capsule())
        }
        .padding(10)
        .background(.white.opacity(MelyFill.card), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
        .layoutProbe("chat.setup", inside: "content")
    }

    /// Stops an answer still coming and forgets the conversation, its files and window.
    private func newConversation() {
        conversation.clear()
        draft = ""
        fieldFocused = true
    }

    private func send() {
        guard !conversation.isStreaming else { return }
        if dictation.isRecording {
            Task { draft = await dictation.finish(); send() }
            return
        }
        conversation.send(draft)
        draft = ""
    }

    private func icon(_ kind: ChatAttachment.Kind) -> String {
        switch kind {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .text: "doc.text"
        }
    }
}

/// Where the messages are scrolled to.
private struct ChatScroll: Equatable {
    /// How far the content is scrolled up past the top edge.
    var fromTop: CGFloat
    /// How much content is left below the bottom edge.
    var toBottom: CGFloat
    /// The content's and the viewport's heights: either one moving is a resize, not a scroll.
    var size: [CGFloat]

    init(_ g: ScrollGeometry) {
        fromTop = g.visibleRect.minY
        toBottom = max(0, g.contentSize.height - g.visibleRect.maxY)
        size = [g.contentSize.height, g.containerSize.height]
    }

    /// Within this of the end the chat keeps following the answer.
    static let followDistance: CGFloat = 24
    static let fade: CGFloat = 12
}

enum ChatStyle {
    /// Claude's orange for the plan, blue for the API.
    static func routeColor(_ route: ChatRoute) -> Color {
        route == .subscription ? Color(red: 0.85, green: 0.47, blue: 0.34) : Color(red: 0.36, green: 0.56, blue: 1.0)
    }
}

/// Route and model: provider chips and the model list.
public struct ChatModelPicker: View {
    let preferences: ChatPreferences
    let openSettings: () -> Void
    let close: () -> Void

    public init(preferences: ChatPreferences, openSettings: @escaping () -> Void, close: @escaping () -> Void) {
        self.preferences = preferences
        self.openSettings = openSettings
        self.close = close
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(ChatRoute.allCases) { route in
                    let on = preferences.route == route
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { preferences.route = route }
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(ChatStyle.routeColor(route)).frame(width: 7, height: 7)
                            Text(route == .subscription ? "Подписка" : "Ключ API")
                                .font(.system(size: MelyType.body, weight: on ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(on ? ChatStyle.routeColor(route).opacity(0.18) : Color.white.opacity(MelyFill.card), in: Capsule())
                        .overlay(Capsule().stroke(on ? ChatStyle.routeColor(route).opacity(0.5) : .white.opacity(MelyFill.raised)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(preferences.setupHint ?? preferences.route.caption)
                .font(.system(size: MelyType.footnote)).foregroundStyle(preferences.setupHint == nil ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            Divider().opacity(0.3)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ChatModel.allCases) { model in
                    let on = preferences.model == model
                    Button {
                        preferences.model = model
                        close()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(model.title).font(.system(size: MelyType.body, weight: on ? .semibold : .regular))
                                Text(model.note).font(.system(size: MelyType.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if on { Image(systemName: "checkmark").font(.system(size: MelyType.caption, weight: .semibold)) }
                        }
                        .foregroundStyle(on ? ChatStyle.routeColor(preferences.route) : .primary)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(on ? ChatStyle.routeColor(preferences.route).opacity(0.1) : .clear,
                                    in: RoundedRectangle(cornerRadius: MelyRadius.small))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Настройки чата…") { close(); openSettings() }
                .buttonStyle(.link).font(.system(size: MelyType.footnote))
        }
        .padding(14)
        .environment(\.colorScheme, .dark)
    }
}

/// The window the chat came from; glows once when it appears.
private struct ContextChip: View {
    let context: ChatContext
    let dismiss: () -> Void
    @State private var glowing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LinearGradient(colors: [.red, .orange, .green, .cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 7, height: 7)
            Text(context.label).font(.system(size: MelyType.footnote)).lineLimit(1)
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(MelyInk.secondary))
                .accessibilityLabel("Не передавать контекст окна")
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(.white.opacity(MelyFill.raised), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(glowing ? 0.75 : 0), lineWidth: 1.5))
        .scaleEffect(glowing ? 1.06 : 1)
        .help(context.windowTitle)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { glowing = true }
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeOut(duration: 0.3)) { glowing = false }
            }
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .user {
            HStack(alignment: .top) {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 3) {
                    if !message.attachments.isEmpty {
                        Text(message.attachments.map { "📎 \($0)" }.joined(separator: "  "))
                            .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.secondary)).lineLimit(1)
                    }
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.system(size: MelyType.body))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: MelyRadius.large))
                    }
                }
            }
        } else {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if message.isSearching {
                        ShimmeringText(text: "Claude ищет в интернете…")
                    }
                    if message.text.isEmpty && message.state == .streaming && !message.isSearching {
                        TypingDots()
                    } else if !message.text.isEmpty {
                        Group {
                            if message.state == .streaming {
                                // Plain text with a blinking cursor while it streams; Markdown once done.
                                TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                                    let show = Int(timeline.date.timeIntervalSinceReferenceDate / 0.5).isMultiple(of: 2)
                                    Text(message.text + (show ? "▌" : " "))
                                        .font(.system(size: MelyType.body))
                                        .foregroundStyle(.white.opacity(MelyInk.strong))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
                                MarkdownText(message.text)
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(.white.opacity(MelyFill.card), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
                    }
                    switch message.state {
                    case .refused:
                        Label("Claude отказался отвечать на этот вопрос", systemImage: "hand.raised")
                            .font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.secondary))
                    case .failed(let error):
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: MelyType.footnote)).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    case .cancelled:
                        Text("остановлено").font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                    case .streaming, .done:
                        EmptyView()
                    }
                }
                Spacer(minLength: 16)
            }
        }
    }
}

private struct TypingDots: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(.white.opacity(MelyInk.tertiary)).frame(width: 5, height: 5)
                    .scaleEffect(phase ? 1.2 : 0.6)
                    .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.14), value: phase)
            }
        }
        .padding(.horizontal, 2).padding(.vertical, 4)
        .onAppear { phase = true }
        .accessibilityLabel("Claude думает")
    }
}

/// A line with light running across it while something works.
private struct ShimmeringText: View {
    let text: String
    @State private var phase: CGFloat = -1

    var body: some View {
        Text(text)
            .font(.system(size: MelyType.body))
            .foregroundStyle(.white.opacity(MelyInk.tertiary))
            .overlay {
                LinearGradient(colors: [.clear, .white.opacity(MelyInk.primary), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 60)
                    .offset(x: phase * 160)
                    .mask(Text(text).font(.system(size: MelyType.body)))
            }
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

private struct SendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 22, height: 22)
            .background(Circle().fill(.white.opacity(configuration.isPressed ? 0.7 : 0.92)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

/// Markdown laid out block by block; inline marks through `AttributedString`.
public struct MarkdownText: View {
    let blocks: [MarkdownBlock]

    public init(_ markdown: String) {
        blocks = ChatMarkdown.blocks(markdown)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder private func view(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text).font(.system(size: level <= 2 ? 15 : 13, weight: .bold))
        case .paragraph(let text):
            inline(text).font(.system(size: MelyType.title)).fixedSize(horizontal: false, vertical: true)
        case .listItem(let ordered, let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ordered.map { "\($0)." } ?? "•").font(.system(size: MelyType.title)).foregroundStyle(.white.opacity(MelyInk.secondary))
                inline(text).font(.system(size: MelyType.title)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 2) {
                if let language {
                    Text(language).font(.system(size: MelyType.micro, weight: .semibold)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text).font(.system(size: MelyType.footnote, design: .monospaced)).foregroundStyle(.white.opacity(MelyInk.primary))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(MelyFill.raised), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
        case .quote(let text):
            inline(text).font(.system(size: MelyType.title)).foregroundStyle(.white.opacity(MelyInk.strong))
                .padding(.leading, 8)
                .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(MelyInk.faint)).frame(width: 2) }
        case .rule:
            Divider().overlay(.white.opacity(0.2))
        }
    }

    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if var attributed = try? AttributedString(markdown: text, options: options) {
            for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
                attributed[run.range].font = .system(size: MelyType.body, design: .monospaced)
                attributed[run.range].backgroundColor = .white.opacity(MelyFill.raised)
            }
            return Text(attributed)
        }
        return Text(text)
    }
}
