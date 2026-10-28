import SwiftUI

/// «Обновить» under the big Mely while a found version waits: the island's peek told about
/// it once, this stays until it is installed. The version is in the tooltip only.
public struct UpdatePill: View {
    let version: String
    let action: () -> Void
    @State private var hovered = false

    public init(version: String, action: @escaping () -> Void) {
        self.version = version
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text("Обновить")
                .font(.system(size: MelyType.caption, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: Self.height)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .background(LinearGradient(colors: [Self.green, Self.blue], startPoint: .leading, endPoint: .trailing)
                        .opacity(hovered ? 0.75 : 0.55), in: Capsule())
        .shadow(color: Self.green.opacity(hovered ? 0.8 : 0.6), radius: 6)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help("Доступна Mely \(version) — установить")
        .accessibilityLabel("Обновить Mely до \(version)")
        .layoutProbe("update.pill", inside: "content", checksText: true)
    }

    static let height: CGFloat = 20
    /// Below the stage's bottom edge: a little air between Mely and the pill.
    static let drop: CGFloat = 16
    /// The green of «Доступна Mely» under the notch, glowing into blue.
    static let green = Color(red: 0.3, green: 0.8, blue: 0.45)
    static let blue = Color(red: 0.2, green: 0.6, blue: 0.9)
}

public extension View {
    /// The big Mely with «Обновить» under it while `version` waits (see `underMely`).
    func updatePill(_ version: String?, action: @escaping () -> Void) -> some View {
        underMely(focus: nil, update: version, action: action)
    }
}
