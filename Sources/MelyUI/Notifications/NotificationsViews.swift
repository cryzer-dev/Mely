import SwiftUI
import AppKit
import MelyCore

/// The "Уведомления" tab: mirrored notifications and calendar news, newest first; a click
/// opens the app (or «Сегодня» for calendar news).
public struct NotificationsView: View {
    let inbox: NotificationInbox
    let open: (NotificationInbox.Item) -> Void

    public init(inbox: NotificationInbox, open: @escaping (NotificationInbox.Item) -> Void) {
        self.inbox = inbox
        self.open = open
    }

    public var body: some View {
        Group {
            if inbox.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "bell.slash").font(.system(size: 18)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                    Text("Пока тихо").font(.system(size: MelyType.title)).foregroundStyle(.white.opacity(MelyInk.secondary))
                    Text("Здесь появятся сообщения и изменения в календаре")
                        .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                }
                .layoutProbe("notifications.empty", inside: "content")
                .islandPart()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .trailing, spacing: 6) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 6) {
                            ForEach(inbox.items) { item in
                                Button { open(item) } label: { NotificationRow(item: item) }
                                    .buttonStyle(.plain)
                                    .layoutProbe("notifications.row.\(item.id)", inside: "notifications.list")
                                    .help(item.isCalendar ? "Открыть «Сегодня»" : "Открыть чат в \(item.appName)")
                            }
                        }
                        .islandPart()
                    }
                    .layoutProbe("notifications.list", inside: "content", scrolls: true)
                    Button("Очистить", action: inbox.clear)
                        .buttonStyle(.plain)
                        .font(.system(size: MelyType.caption, weight: .medium))
                        .foregroundStyle(.white.opacity(MelyInk.secondary))
                        .layoutProbe("notifications.clear", inside: "content")
                        .islandPart(spacing: 6)
                }
            }
        }
        .foregroundStyle(.white)
        // Looking at the list is reading it.
        .onAppear { inbox.markSeen() }
        .onChange(of: inbox.items.first?.id) { inbox.markSeen() }
    }
}

private struct NotificationRow: View {
    let item: NotificationInbox.Item

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.title).font(.system(size: MelyType.body, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(item.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                        .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                        .fixedSize()
                }
                Text(item.text).font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.strong)).lineLimit(2)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.white.opacity(MelyFill.card), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.isCalendar ? "Открыть «Сегодня»" : "Открыть \(item.appName)")
    }

    /// The app's icon; calendar news gets its symbol in a circle, as under the notch.
    @ViewBuilder private var icon: some View {
        switch item.kind {
        case .app(let bundleId, _):
            AppIcon(bundleId: bundleId)
        case .calendar(_, let symbol, _):
            Image(systemName: symbol)
                .font(.system(size: MelyType.caption, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Self.tint(symbol).opacity(0.22), in: Circle())
                .foregroundStyle(Self.tint(symbol))
        }
    }

    /// The colours of the calendar previews: new blue, moved orange, cancelled red.
    static func tint(_ symbol: String) -> Color {
        switch symbol {
        case "calendar.badge.clock": Color(red: 1.0, green: 0.6, blue: 0.2)
        case "calendar.badge.minus": Color(red: 1.0, green: 0.38, blue: 0.35)
        default: Color(red: 0.36, green: 0.56, blue: 1.0)
        }
    }
}

struct AppIcon: View {
    let bundleId: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: "app.badge").resizable().scaledToFit().foregroundStyle(.white.opacity(MelyInk.secondary))
        }
    }
}

/// Which apps to mirror, privacy and Focus. Tells how to keep banners from showing twice.
public struct NotificationMirrorSettingsView: View {
    public struct Candidate: Identifiable, Sendable {
        public let id: String
        public let name: String
        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    @Bindable var settings: NotificationMirrorSettings
    let candidates: [Candidate]
    let openSystemNotifications: () -> Void
    let close: () -> Void

    public init(settings: NotificationMirrorSettings, candidates: [Candidate],
                openSystemNotifications: @escaping () -> Void, close: @escaping () -> Void) {
        self.settings = settings
        self.candidates = candidates
        self.openSystemNotifications = openSystemNotifications
        self.close = close
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Уведомления в челке").font(.title3.weight(.semibold))
            Text("Mely показывает уведомления, которые macOS получает от выбранных приложений. Он только читает их и никуда не отправляет.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(candidates) { app in
                    Toggle(isOn: Binding(
                        get: { settings.apps.contains(app.id) },
                        set: { on in if on { settings.apps.insert(app.id) } else { settings.apps.remove(app.id) } })) {
                        HStack(spacing: 8) {
                            AppIcon(bundleId: app.id).frame(width: 18, height: 18)
                            Text(app.name)
                        }
                    }
                }
            }
            .frame(height: 220)
            Toggle("Скрывать текст сообщений", isOn: $settings.hideText)
            Toggle("В фокус-режиме не показывать, только считать", isOn: $settings.quietInFocus)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb").foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Чтобы уведомление не показывалось дважды, поставьте выбранным приложениям стиль «Нет» в Системных настройках → Уведомления. Не выключайте уведомления совсем: тогда они не дойдут и до Mely.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Button("Открыть настройки уведомлений", action: openSystemNotifications).buttonStyle(.link)
                }
            }
            HStack {
                Spacer()
                Button("Готово", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
