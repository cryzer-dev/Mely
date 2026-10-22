import SwiftUI
import AppKit
import MelyCore

struct PeekView: View {
    let content: PeekContent
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                title
                Text(content.subtitle).font(.system(size: MelyType.body)).foregroundStyle(.white.opacity(MelyInk.strong)).lineLimit(2)
            }
            .layoutProbe("peek.text", inside: "peek", checksText: true)
            Spacer(minLength: 0)
            if let action = content.actionTitle {
                Text(action)
                    .font(.system(size: MelyType.body, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white, in: Capsule())
                    .accessibilityAddTraits(.isButton)
            }
            if content.until != nil, let dismiss {
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

    /// The title; a reminder's counts down to its meeting.
    @ViewBuilder private var title: some View {
        if let until = content.until {
            TimelineView(.periodic(from: .now, by: 10)) { context in
                Text(content.title + " · " + MeetingCountdown.text(until: until, now: context.date))
                    .font(.system(size: MelyType.title, weight: .semibold)).lineLimit(1)
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
        }
    }
}
