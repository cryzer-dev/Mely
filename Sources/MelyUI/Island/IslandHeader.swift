import SwiftUI
import MelyCore

/// The expanded island's top row, level with the notch (task 7.9): the
/// sections as icon capsules left of the notch; the plan, sound, settings and «×» right
/// of it. The notch itself stays empty in the middle.
public struct IslandHeader: View {
    /// A section of the expanded island.
    public struct Item: Identifiable {
        public let tab: IslandTabs.Tab
        public let icon: String
        public let title: String
        public var badge: Int
        public var id: IslandTabs.Tab { tab }

        public init(_ tab: IslandTabs.Tab, icon: String, title: String, badge: Int = 0) {
            self.tab = tab
            self.icon = icon
            self.title = title
            self.badge = badge
        }
    }

    let tabs: IslandTabs
    let items: [Item]
    let usage: PlanUsageStore?
    let soundOn: Bool
    /// A request waits: the island cannot fold, so no «×».
    let heldOpen: Bool
    /// A new Mely version waits: a dot on the gear.
    let updateAvailable: Bool
    let toggleSound: () -> Void
    let openSettings: () -> Void
    let close: () -> Void
    @Environment(\.islandNotchWidth) private var notchWidth
    /// The limits card under the pill.
    @State private var showsUsage = false

    public init(tabs: IslandTabs, items: [Item], usage: PlanUsageStore?, soundOn: Bool, heldOpen: Bool,
                updateAvailable: Bool = false, showsUsage: Bool = false,
                toggleSound: @escaping () -> Void, openSettings: @escaping () -> Void, close: @escaping () -> Void) {
        _showsUsage = State(initialValue: showsUsage)
        self.tabs = tabs
        self.items = items
        self.usage = usage
        self.soundOn = soundOn
        self.heldOpen = heldOpen
        self.updateAvailable = updateAvailable
        self.toggleSound = toggleSound
        self.openSettings = openSettings
        self.close = close
    }

    public var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(items) { item in
                    HeaderTab(item: item, isOn: tabs.selected == item.tab) {
                        showsUsage = false
                        if item.tab == .chat { tabs.showChat() } else { tabs.selected = item.tab }
                    }
                    .layoutProbe("header.tab.\(item.tab)", row: "header", inside: "island")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The notch.
            Color.clear.frame(width: notchWidth)
                .layoutProbe("header.notch", row: "header")
            HStack(spacing: 4) {
                if let usage {
                    Button { showsUsage.toggle() } label: {
                        CompactPlanGauge(usage: usage.usage, showsEmpty: true)
                            .padding(.horizontal, 7).frame(height: 22)
                            .background(.white.opacity(showsUsage ? 0.16 : 0.07), in: Capsule())
                            .contentShape(Capsule())
                            .layoutProbe("header.usage", row: "header", inside: "island", contains: "plan.gauge")
                    }
                    .buttonStyle(.plain)
                    .help("Лимиты Claude: какой, сколько и когда сброс")
                    .overlay(alignment: .topTrailing) {
                        if showsUsage {
                            PlanUsageCard(usage: usage.usage)
                                .offset(y: 28)
                                .layoutProbe("plan.card", inside: "island")
                                .onTapGesture { showsUsage = false }
                                .transition(.opacity.combined(with: .offset(y: -4)))
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: showsUsage)
                    .padding(.trailing, 4)
                }
                HeaderIcon(icon: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                           help: soundOn ? "Выключить звуки" : "Включить звуки", action: toggleSound)
                    .layoutProbe("header.sound", row: "header", inside: "island")
                HeaderIcon(icon: "gearshape.fill", help: updateAvailable ? "Настройки · есть новая версия Mely" : "Настройки",
                           dot: updateAvailable, action: openSettings)
                    .layoutProbe("header.settings", row: "header", inside: "island")
                if !heldOpen {
                    HeaderIcon(icon: "xmark", help: "Свернуть (Esc)", action: close)
                        .layoutProbe("header.close", row: "header", inside: "island")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
    }
}

/// One section: an icon in a capsule, lit when chosen, with a count for unread messages.
private struct HeaderTab: View {
    let item: IslandHeader.Item
    let isOn: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: { MelyHaptics.tap(); action() }) {
            Image(systemName: item.icon)
                .font(.system(size: MelyType.body, weight: .semibold))
                .foregroundStyle(.white.opacity(isOn ? 1 : hovered ? 0.75 : 0.5))
                .frame(width: 32, height: 22)
                .background(.white.opacity(isOn ? 0.16 : hovered ? 0.07 : 0), in: Capsule())
                .overlay(alignment: .topTrailing) {
                    if item.badge > 0 {
                        Text(item.badge > 9 ? "9+" : "\(item.badge)")
                            .font(.system(size: 8.5, weight: .bold)).monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3.5).frame(minWidth: 13, minHeight: 13)
                            .background(Color(red: 1.0, green: 0.38, blue: 0.35), in: Capsule())
                            .offset(x: 3, y: -4)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isOn)
        .help(item.title)
        .accessibilityLabel(item.title + (item.badge > 0 ? ", новых: \(item.badge)" : ""))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// A plain icon button on the right of the header.
private struct HeaderIcon: View {
    let icon: String
    let help: String
    /// A small green dot in the corner (a new version): unlike a tab's red count.
    var dot = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: { MelyHaptics.tap(); action() }) {
            Image(systemName: icon)
                .font(.system(size: MelyType.body, weight: .semibold))
                .foregroundStyle(.white.opacity(hovered || dot ? 0.95 : 0.5))
                .frame(width: 26, height: 22)
                .background(.white.opacity(hovered ? 0.07 : 0), in: Capsule())
                .overlay(alignment: .topTrailing) {
                    if dot {
                        Circle().fill(Color(red: 0.35, green: 0.85, blue: 0.55))
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(.black, lineWidth: 1.5))
                            .offset(x: -3, y: 2)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct IslandNotchWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 200
}

public extension EnvironmentValues {
    /// The notch's width: the header keeps that gap empty in its middle.
    var islandNotchWidth: CGFloat {
        get { self[IslandNotchWidthKey.self] }
        set { self[IslandNotchWidthKey.self] = newValue }
    }
}
