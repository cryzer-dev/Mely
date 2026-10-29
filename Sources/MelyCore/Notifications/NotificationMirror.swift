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

    /// - Parameter suppressed: apps Mely shows itself right now (Reminders while the tasks
    ///   remind under the notch): never mirrored, so nothing comes twice.
    /// - Parameter holding: a Mely focus session runs: kept in the list, no preview.
    public static func decide(_ n: MirroredNotification, apps: Set<String>, suppressed: Set<String> = [], hideText: Bool,
                              quietInFocus: Bool, focusOn: Bool, holding: Bool = false, appName: String) -> MirrorDecision {
        // The database keeps bundle ids lowercased ("com.apple.scripteditor2").
        func has(_ ids: Set<String>) -> Bool { ids.contains { $0.caseInsensitiveCompare(n.bundleId) == .orderedSame } }
        guard has(apps), !has(suppressed) else { return .ignore }
        if quietInFocus && focusOn || holding { return .collect }
        let title = n.title ?? appName
        if hideText { return .preview(title: title, text: n.subtitle.map { "\(appName) · \($0)" } ?? "Новое уведомление") }
        // A browser puts the site in the subtitle; a messenger the chat or nothing.
        let text = [n.subtitle, n.body].compactMap { $0 }.joined(separator: " — ")
        return .preview(title: title, text: text.isEmpty ? appName : text)
    }
}

/// Messages held back from previews while a focus session runs; one summary when it ends.
public struct MessageHold: Equatable, Sendable {
    public private(set) var count = 0

    public init() {}

    public mutating func add() { count += 1 }

    /// The count so far, reset.
    public mutating func release() -> Int {
        defer { count = 0 }
        return count
    }

    /// «Пока ты работал: 3 сообщения».
    public static func summary(_ n: Int) -> String {
        let tens = n % 100, ones = n % 10
        let word: String = if (11...14).contains(tens) { "сообщений" } else {
            switch ones {
            case 1: "сообщение"
            case 2...4: "сообщения"
            default: "сообщений"
            }
        }
        return "Пока ты работал: \(n) \(word)"
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
