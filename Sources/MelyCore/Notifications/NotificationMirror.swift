import Foundation
import Observation
import OSLog

private let watcherLog = Logger(subsystem: "dev.mely.app", category: "notifications")

/// What to mirror and how.
@MainActor
@Observable
public final class NotificationMirrorSettings {
    /// Bundle ids whose notifications show in the notch.
    public var apps: Set<String> { didSet { save() } }
    /// Only the app and the sender, never the text.
    public var hideText: Bool { didSet { save() } }
    /// While a Focus (Do Not Disturb) is on, no previews: notifications only count up.
    public var quietInFocus: Bool { didSet { save() } }

    /// Messengers and apps offered first in the list (Claude: answers from its chats).
    public static let suggested: [(id: String, name: String)] = [
        ("ru.keepcoder.Telegram", "Telegram"),
        ("org.telegram.desktop", "Telegram Desktop"),
        ("com.anthropic.claudefordesktop", "Claude"),
        ("ru.yandex.desktop.telemost", "Телемост"),
        ("ru.yandex.yamb", "Яндекс Мессенджер"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("net.whatsapp.WhatsApp", "WhatsApp"),
        ("com.google.Chrome", "Google Chrome"),
        ("com.apple.Safari", "Safari"),
        ("ru.yandex.desktop.yandex-browser", "Яндекс Браузер"),
        ("company.thebrowser.Browser", "Arc"),
    ]
    /// On from the start, when installed: the messengers (Telemost's chats too) and
    /// Claude's chat answers.
    static let onByDefault: Set<String> = ["ru.keepcoder.Telegram", "org.telegram.desktop", "com.anthropic.claudefordesktop",
                                           "ru.yandex.desktop.telemost"]

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "notificationMirror"
    /// Bumped when a list saved by an older version needs fixing (`migrate`).
    static let version = 2

    public init(defaults: UserDefaults = .standard, installed: (String) -> Bool = { _ in true }) {
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: Self.key)
        let stored = saved?["apps"] as? [String]
        apps = stored.map { Self.migrate(Set($0), from: saved?["version"] as? Int ?? 1, installed: installed) }
            ?? Self.onByDefault.filter(installed)
        hideText = saved?["hideText"] as? Bool ?? false
        quietInFocus = saved?["quietInFocus"] as? Bool ?? true
        if stored != nil, (saved?["version"] as? Int ?? 1) < Self.version { save() }
    }

    /// Version 1 had Yandex Messenger under a wrong id (`ru.yandex.messenger`, so it never
    /// matched) and no Telemost: the id is fixed and Telemost comes on, once.
    static func migrate(_ apps: Set<String>, from version: Int, installed: (String) -> Bool) -> Set<String> {
        guard version < 2 else { return apps }
        var apps = apps
        if apps.remove("ru.yandex.messenger") != nil { apps.insert("ru.yandex.yamb") }
        if installed("ru.yandex.desktop.telemost") { apps.insert("ru.yandex.desktop.telemost") }
        return apps
    }

    private func save() {
        defaults.set(["apps": apps.sorted(), "hideText": hideText, "quietInFocus": quietInFocus, "version": Self.version],
                     forKey: Self.key)
    }
}

/// What the notch does with one notification.
public enum MirrorDecision: Equatable, Sendable {
    case ignore
    /// Focus is on: count it in the overview, no preview.
    case collect
    case preview(title: String, text: String)

    public static func decide(_ n: MirroredNotification, apps: Set<String>, hideText: Bool,
                              quietInFocus: Bool, focusOn: Bool, appName: String) -> MirrorDecision {
        // The database keeps bundle ids lowercased ("com.apple.scripteditor2").
        guard apps.contains(where: { $0.caseInsensitiveCompare(n.bundleId) == .orderedSame }) else { return .ignore }
        if quietInFocus && focusOn { return .collect }
        let title = n.title ?? appName
        if hideText { return .preview(title: title, text: n.subtitle.map { "\(appName) · \($0)" } ?? "Новое уведомление") }
        // A browser puts the site in the subtitle; a messenger the chat or nothing.
        let text = [n.subtitle, n.body].compactMap { $0 }.joined(separator: " — ")
        return .preview(title: title, text: text.isEmpty ? appName : text)
    }
}

/// Focus / Do Not Disturb, from the file macOS keeps its active assertions in (under Full
/// Disk Access, which the mirror has anyway). Unreadable or unknown → treated as off.
public enum SystemFocus {
    public static let assertionsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")

    public static func isOn(url: URL = assertionsURL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else { return false }
        return entries.contains { !(($0["storeAssertionRecords"] as? [Any]) ?? []).isEmpty }
    }
}

/// Watches the database for new rows: a file event on its WAL right away, a 2 s poll in
/// case events are missed. Starts at the newest row: what came before is not replayed.
public final class NotificationWatcher: @unchecked Sendable {
    public let database: NotificationDatabase
    private let queue = DispatchQueue(label: "dev.mely.notifications")
    private var cursor: Int64 = 0
    private var walSource: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private let deliver: @Sendable (Result<[MirroredNotification], NotificationDatabase.Failure>) -> Void

    /// - Parameter deliver: new notifications, or why the database cannot be read (on a
    ///   background queue).
    public init(database: NotificationDatabase = NotificationDatabase(),
                deliver: @escaping @Sendable (Result<[MirroredNotification], NotificationDatabase.Failure>) -> Void) {
        self.database = database
        self.deliver = deliver
    }

    /// Fails right away when the database cannot be read (no access, unknown format).
    public func start() throws {
        cursor = try database.latestId()
        queue.async { self.watchWAL() }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in self?.check() }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel(); timer = nil
        walSource?.cancel(); walSource = nil
    }

    /// Reads what came after the cursor. Called by the WAL event, the timer, and tests.
    public func check() {
        do {
            let fresh = try database.notifications(after: cursor)
            let latest = (try? database.latestId()) ?? -1
            watcherLog.debug("check cursor=\(self.cursor, privacy: .public) latest=\(latest, privacy: .public) fetched=\(fresh.count, privacy: .public)")
            guard let last = fresh.last else { return }
            cursor = last.id
            deliver(.success(fresh))
        } catch let failure as NotificationDatabase.Failure {
            deliver(.failure(failure))
        } catch {
            deliver(.failure(.incompatible(error.localizedDescription)))
        }
    }

    /// The WAL is rewritten and replaced: re-arm on delete or rename.
    private func watchWAL() {
        walSource?.cancel()
        let wal = database.url.path + "-wal"
        let fd = open(wal, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename],
                                                               queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            if !source.data.intersection([.delete, .rename]).isEmpty {
                self.queue.asyncAfter(deadline: .now() + 0.5) { self.watchWAL() }
            }
            // Let usernoted finish its write before reading.
            self.queue.asyncAfter(deadline: .now() + 0.15) { self.check() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        walSource = source
    }
}

/// Mirrored notifications kept for the overview: in memory only, never written anywhere.
@MainActor
@Observable
public final class MirroredMessages {
    public struct Item: Identifiable, Equatable, Sendable {
        public let id: Int64
        public let uuid: String?
        public let bundleId: String
        public let appName: String
        public let title: String
        public let text: String
        public let date: Date
    }

    public private(set) var items: [Item] = []
    /// Arrived since the overview was last looked at (in Focus, the only trace of them).
    public private(set) var unseen = 0
    public static let keep = 30

    public init() {}

    public func add(_ n: MirroredNotification, appName: String, title: String, text: String) {
        items.insert(Item(id: n.id, uuid: n.uuid, bundleId: n.bundleId, appName: appName, title: title, text: text,
                          date: n.deliveredAt), at: 0)
        if items.count > Self.keep { items.removeLast(items.count - Self.keep) }
        unseen += 1
    }

    public func markSeen() { unseen = 0 }

    /// Keeps only what Notification Center still has: read or dismissed ones go.
    public func keep(only ids: Set<Int64>) {
        let before = items.count
        items.removeAll { !ids.contains($0.id) }
        unseen = max(0, unseen - (before - items.count))
    }

    public func remove(_ id: Int64) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        unseen = max(0, unseen - 1)
    }
    public func clear() { items = []; unseen = 0 }
}
