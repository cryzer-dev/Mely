import SwiftUI
import MelyCore

/// «Что нового в Mely 1.6»: the release's tiles, once, in place of the island's page.
public struct WhatsNewView: View {
    let card: WhatsNew
    /// «Попробовать задачи»: switches the tasks on if needed and opens them.
    let tryTasks: () -> Void
    /// «Понятно» and «×».
    let done: () -> Void
    /// «Подробнее ↗»: the release page; nil hides it.
    let more: (() -> Void)?

    public init(card: WhatsNew, tryTasks: @escaping () -> Void, done: @escaping () -> Void, more: (() -> Void)? = nil) {
        self.card = card
        self.tryTasks = tryTasks
        self.done = done
        self.more = more
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Что нового в Mely \(card.version)").font(.system(size: MelyType.headline, weight: .bold))
                Spacer(minLength: 8)
                Button(action: done) {
                    Image(systemName: "xmark").font(.system(size: MelyType.caption, weight: .bold))
                        .foregroundStyle(.white.opacity(MelyInk.secondary))
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Закрыть")
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(card.items, id: \.title) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        // One height for every symbol: the titles stand on one line.
                        Image(systemName: item.symbol).font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(MelyTint.working)
                            .frame(height: 24, alignment: .leading)
                        Text(item.title).font(.system(size: MelyType.title, weight: .semibold)).lineLimit(1)
                        Text(item.text).font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                    .background(.white.opacity(MelyFill.card), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
                    .layoutProbe("whatsnew.item.\(item.title)", inside: "whatsnew", checksText: true)
                }
            }
            HStack(spacing: 8) {
                button("Попробовать задачи", prominent: true, action: tryTasks)
                button("Понятно", prominent: false, action: done)
                Spacer(minLength: 4)
                if let more {
                    Button("Подробнее ↗", action: more)
                        .buttonStyle(.plain)
                        .font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.secondary))
                        .fixedSize()
                }
            }
            .layoutProbe("whatsnew.buttons", inside: "whatsnew")
        }
        .foregroundStyle(.white)
        .padding(.top, 6)
        .layoutProbe("whatsnew", inside: "content")
        .islandPart()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func button(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: MelyType.footnote, weight: .semibold))
                .foregroundStyle(prominent ? .black : .white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(prominent ? Color.white : Color.white.opacity(MelyFill.selected), in: Capsule())
                .fixedSize()
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
