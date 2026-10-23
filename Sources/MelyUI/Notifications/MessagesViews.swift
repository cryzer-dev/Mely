import SwiftUI
import AppKit
import MelyCore

/// The "Сообщения" tab: mirrored notifications, newest first; a click opens the app.
public struct MessagesView: View {
    let messages: MirroredMessages
    /// Opens the app behind the notification with this id.
    let open: (Int64) -> Void

    public init(messages: MirroredMessages, open: @escaping (Int64) -> Void) {
        self.messages = messages
        self.open = open
    }

    public var body: some View {
        Group {
            if messages.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "bell.slash").font(.system(size: 18)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                    Text("Пока тихо").font(.system(size: MelyType.title)).foregroundStyle(.white.opacity(MelyInk.secondary))
                    Text("Здесь появятся уведомления выбранных приложений")
                        .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                }
                .layoutProbe("messages.empty", inside: "content")
                .islandPart()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .trailing, spacing: 6) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 6) {
                            ForEach(messages.items) { item in
                                Button { open(item.id) } label: { MessageRow(item: item) }
                                    .buttonStyle(.plain)
                                    .layoutProbe("messages.row.\(item.id)", inside: "messages.list")
                                    .help("Открыть чат в \(item.appName)")
                            }
                        }
                        .islandPart()
                    }
                    .layoutProbe("messages.list", inside: "content", scrolls: true)
                    Button("Очистить", action: messages.clear)
                        .buttonStyle(.plain)
                        .font(.system(size: MelyType.caption, weight: .medium))
                        .foregroundStyle(.white.opacity(MelyInk.secondary))
                        .layoutProbe("messages.clear", inside: "content")
                        .islandPart(spacing: 6)
                }
            }
        }
        .foregroundStyle(.white)
        // Looking at the list is reading it.
        .onAppear { messages.markSeen() }
        .onChange(of: messages.items.first?.id) { messages.markSeen() }
    }
}

private struct MessageRow: View {
    let item: MirroredMessages.Item

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppIcon(bundleId: item.bundleId).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.title).font(.system(size: MelyType.body, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(item.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                        .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                }
                Text(item.text).font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.strong)).lineLimit(2)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.white.opacity(MelyFill.card), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Открыть \(item.appName)")
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
