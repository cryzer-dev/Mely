import Foundation
import Observation
import OSLog

private let inboxLog = Logger(subsystem: "dev.mely.app", category: "notifications")

/// The "Уведомления" tab: mirrored notifications of other apps and Mely's own news about
/// the calendar, newest first. Kept on this Mac only, as shown (hidden text stays hidden).
@MainActor
@Observable
public final class NotificationInbox {
    public struct Item: Identifiable, Equatable, Sendable, Codable {
        public enum Kind: Equatable, Sendable, Codable {
            /// A row of Notification Center's database: goes once read or dismissed there.
            case app(bundleId: String, recordId: Int64)
            /// News about an event: goes once the event is over.
            case calendar(eventId: String, symbol: String, ends: Date)
        }

        /// `nc-<rec_id>` or `cal-<event id>`: the two never collide.
        public let id: String
        public let kind: Kind
        public let appName: String
        public let title: String
        public let text: String
        public let date: Date

        public init(id: String, kind: Kind, appName: String, title: String, text: String, date: Date) {
            self.id = id
            self.kind = kind
            self.appName = appName
            self.title = title
            self.text = text
            self.date = date
        }

        public var bundleId: String? {
            if case .app(let bundleId, _) = kind { return bundleId }
            return nil
        }

        public var isCalendar: Bool {
            if case .calendar = kind { return true }
            return false
        }
    }

    public private(set) var items: [Item] = []
    /// Arrived since the tab was last looked at (in Focus, the only trace of them).
    public private(set) var unseen = 0
    public static let keep = 30

    /// Where the list survives a restart; nil keeps it in memory only, and setting nil
    /// deletes what was saved.
    public var fileURL: URL? {
        didSet {
            guard fileURL != oldValue else { return }
            if let oldValue { Self.delete(oldValue) }
            scheduleSave()
        }
    }
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let saved = try JSONDecoder().decode(Saved.self, from: data)
            items = Array(saved.items.prefix(Self.keep))
            unseen = min(saved.unseen, items.count)
        } catch {
            inboxLog.error("saved notifications unreadable, starting empty")
        }
    }

    public static func appId(_ recordId: Int64) -> String { "nc-\(recordId)" }

    public func add(_ n: MirroredNotification, appName: String, title: String, text: String) {
        insert(Item(id: Self.appId(n.id), kind: .app(bundleId: n.bundleId, recordId: n.id), appName: appName,
                    title: title, text: text, date: n.deliveredAt))
    }

    /// News about an event; a newer one about the same event takes its place.
    public func addCalendar(eventId: String, symbol: String, title: String, text: String, ends: Date, date: Date = Date()) {
        insert(Item(id: "cal-\(eventId)", kind: .calendar(eventId: eventId, symbol: symbol, ends: ends), appName: "Календарь",
                    title: title, text: text, date: date))
    }

    private func insert(_ item: Item) {
        if items.contains(where: { $0.id == item.id }) { remove(item.id) }
        items.insert(item, at: 0)
        if items.count > Self.keep { items.removeLast(items.count - Self.keep) }
        unseen += 1
        scheduleSave()
    }

    public func markSeen() {
        guard unseen != 0 else { return }
        unseen = 0
        scheduleSave()
    }

    /// Notification Center rows still in the list, for `keepApps(only:)`.
    public var appRecordIds: [Int64] {
        items.compactMap { if case .app(_, let id) = $0.kind { id } else { nil } }
    }

    /// Keeps only the app notifications Notification Center still has: read or dismissed
    /// ones go. Calendar news is not its business.
    public func keepApps(only recordIds: Set<Int64>) {
        drop { if case .app(_, let id) = $0.kind { !recordIds.contains(id) } else { false } }
    }

    /// Calendar news about events that are over.
    public func dropEnded(now: Date = Date()) {
        drop { if case .calendar(_, _, let ends) = $0.kind { ends <= now } else { false } }
    }

    public func removeApps() { drop { !$0.isCalendar } }
    public func removeCalendar() { drop(\.isCalendar) }

    public func remove(_ id: String) { drop { $0.id == id } }

    /// Empties the list and what was saved of it.
    public func clear() {
        pendingSave?.cancel()
        items = []
        unseen = 0
        if let fileURL { Self.delete(fileURL) }
    }

    private func drop(_ gone: (Item) -> Bool) {
        let before = items.count
        items.removeAll(where: gone)
        guard items.count != before else { return }
        unseen = max(0, unseen - (before - items.count))
        scheduleSave()
    }

    // MARK: Saving

    private struct Saved: Codable {
        var version = 1
        let items: [Item]
        let unseen: Int
    }

    /// A burst of notifications is one write, a second later.
    private func scheduleSave() {
        guard fileURL != nil else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes the list right away (on quit, in tests).
    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Saved(items: items, unseen: unseen))
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            inboxLog.error("cannot save notifications: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// `~/Library/Application Support/Mely/notifications.json`.
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mely", isDirectory: true).appendingPathComponent("notifications.json")
    }
}

/// What goes into the "Уведомления" tab and whether it survives a restart.
@MainActor
@Observable
public final class InboxSettings {
    /// Notifications of the chosen apps.
    public var keepsMessages: Bool { didSet { save() } }
    /// «Новое событие», «Перенесено», «Отменено».
    public var keepsCalendar: Bool { didSet { save() } }
    /// Saved on this Mac, back after a restart.
    public var persists: Bool { didSet { save() } }
    /// Told after every change, to apply it to the list.
    @ObservationIgnored public var changed: (() -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "notificationInbox"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: Self.key)
        keepsMessages = saved?["messages"] as? Bool ?? true
        keepsCalendar = saved?["calendar"] as? Bool ?? true
        persists = saved?["persists"] as? Bool ?? true
    }

    private func save() {
        defaults.set(["messages": keepsMessages, "calendar": keepsCalendar, "persists": persists], forKey: Self.key)
        changed?()
    }
}

public extension NotificationInbox {
    /// Drops what the settings no longer keep and saves or forgets the file.
    func apply(_ settings: InboxSettings, fileURL url: URL = NotificationInbox.defaultURL) {
        if !settings.keepsMessages { removeApps() }
        if !settings.keepsCalendar { removeCalendar() }
        fileURL = settings.persists ? url : nil
    }
}
