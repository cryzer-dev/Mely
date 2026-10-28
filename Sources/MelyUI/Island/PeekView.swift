import SwiftUI
import AppKit
import MelyCore

struct PeekView: View {
    let content: PeekContent
    var dismiss: (() -> Void)?
    /// A button, by its action id.
    var run: ((String) -> Void)?

    var body: some View {
        let folded = Self.folded(content)
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                title
                Text(content.subtitle).font(.system(size: MelyType.body)).foregroundStyle(.white.opacity(MelyInk.strong)).lineLimit(2)
            }
            // Ahead of the spacer: the title takes the room it needs before the gap does.
            .layoutPriority(1)
            .layoutProbe("peek.text", inside: "peek", checksText: true)
            Spacer(minLength: 0)
            if !folded.isEmpty {
                Menu {
                    ForEach(folded) { action in Button(action.title) { run?(action.id) } }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: MelyType.body, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(MelyFill.selected), in: Circle())
                        .contentShape(Circle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Ещё")
                .accessibilityLabel("Ещё действия")
                .layoutProbe("peek.more", row: "peek.buttons", inside: "peek", checksWhole: true)
            }
            ForEach(content.actions.filter { !folded.contains($0) }) { action in
                button(action)
            }
            // A lasting preview (a reminder) closes with «×»; a passing one goes by itself.
            if content.lastsUntil != nil, let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: MelyType.caption, weight: .bold))
                        .foregroundStyle(.white.opacity(MelyInk.secondary))
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(MelyFill.raised), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Закрыть напоминание")
                .accessibilityLabel("Закрыть напоминание")
            }
        }
        .foregroundStyle(.white)
        .frame(height: IslandPresentation.peekBodyHeight)
    }

    /// Never squeezed: the title gives way instead. A sole button is the whole preview.
    @ViewBuilder private func button(_ action: PeekAction) -> some View {
        let label = Text(action.title)
            .lineLimit(1)
            .fixedSize()
            .font(.system(size: MelyType.body, weight: .semibold))
            .foregroundStyle(action.isPrimary ? .black : .white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(action.isPrimary ? .white : .white.opacity(MelyFill.selected), in: Capsule())
            .layoutProbe(Self.probe(action), row: "peek.buttons", inside: "peek", checksWhole: true)
        if content.soleAction != nil {
            label.accessibilityAddTraits(.isButton)
        } else {
            Button { run?(action.id) } label: { label.contentShape(Capsule()) }.buttonStyle(.plain)
        }
    }

    private static func probe(_ action: PeekAction) -> String {
        switch action.id {
        case PeekAction.primaryId: "peek.action"
        case PeekAction.secondaryId: "peek.secondary"
        default: "peek.action.\(action.id)"
        }
    }

    /// The title keeps at least this much beside the buttons.
    static let minTextWidth: CGFloat = 150

    /// What goes into «⋯»: the folding buttons, once all of them do not fit beside the
    /// icon, «×» and `minTextWidth` of title.
    static func folded(_ content: PeekContent) -> [PeekAction] {
        let font = NSFont.systemFont(ofSize: MelyType.body, weight: .semibold)
        func width(_ a: PeekAction) -> CGFloat {
            (a.title as NSString).size(withAttributes: [.font: font]).width.rounded(.up) + 24 + 12
        }
        let close: CGFloat = content.lastsUntil != nil ? 22 + 12 : 0
        let room = IslandPresentation.peekWidth - 2 * 16 - (30 + 12) - close - minTextWidth
        guard content.actions.reduce(0, { $0 + width($1) }) > room else { return [] }
        return content.actions.filter(\.folds)
    }

    /// The title; a reminder's counts down to its meeting. A long title gives way: the
    /// countdown always shows whole.
    @ViewBuilder private var title: some View {
        if let until = content.until {
            TimelineView(.periodic(from: .now, by: 10)) { context in
                HStack(spacing: 0) {
                    Text(content.title).lineLimit(1)
                    Text(" · " + MeetingCountdown.text(until: until, now: context.date)).lineLimit(1).fixedSize()
                        .layoutProbe("peek.countdown", inside: "peek", checksWhole: true)
                }
                .font(.system(size: MelyType.title, weight: .semibold))
            }
        } else {
            Text(content.title).font(.system(size: MelyType.title, weight: .semibold)).lineLimit(1)
        }
    }

    @ViewBuilder private var icon: some View {
        if let data = content.artwork, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: MelyRadius.small))
        } else if let id = content.appBundleId, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 30, height: 30)
        } else {
            Image(systemName: content.symbol)
                .font(.system(size: MelyType.headline, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(color.opacity(0.22), in: Circle())
                .foregroundStyle(color)
        }
    }

    private var color: Color {
        switch content.tint {
        case .blue: Color(red: 0.36, green: 0.56, blue: 1.0)
        case .green: Color(red: 0.3, green: 0.8, blue: 0.45)
        case .orange: Color(red: 1.0, green: 0.6, blue: 0.2)
        case .red: Color(red: 1.0, green: 0.38, blue: 0.35)
        case .yellow: Color(red: 0.95, green: 0.75, blue: 0.2)
        case .gray: Color(white: 0.6)
        case .focus: MelyTint.focus
        case .rest: MelyTint.rest
        }
    }
}
