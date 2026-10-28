import Testing
import Foundation
import SQLite3
@testable import MelyCore

/// A database with the `usernoted` schema (macOS 26): `app` and `record`.
private final class FixtureDB {
    let dir: URL
    let url: URL
    private var db: OpaquePointer?
    private var nextUUID = 1

    init(schema: Bool = true) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mely-notif-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("db")
        sqlite3_open(url.path, &db)
        if schema {
            exec("create table app (app_id integer primary key, identifier text)")
            exec("create table record (rec_id integer primary key, app_id integer, uuid blob, data blob, delivered_date real)")
        }
    }

    deinit {
        sqlite3_close(db)
        try? FileManager.default.removeItem(at: dir)
    }

    func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }

    func add(app: String, title: Any?, subtitle: Any? = nil, body: Any?, delivered: Date = Date()) {
        exec("insert or ignore into app (identifier) values ('\(app)')")
        var req: [String: Any] = [:]
        if let title { req["titl"] = title }
        if let subtitle { req["subt"] = subtitle }
        if let body { req["body"] = body }
        let data = try! PropertyListSerialization.data(fromPropertyList: ["app": app, "req": req], format: .binary, options: 0)
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "insert into record (app_id, data, delivered_date, uuid) values ((select app_id from app where identifier = ?1), ?2, ?3, ?4)", -1, &stmt, nil)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, app, -1, transient)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(data.count), transient) }
        sqlite3_bind_double(stmt, 3, delivered.timeIntervalSince1970 - 978_307_200)
        let uuid = withUnsafeBytes(of: UUID(uuidString: "A1B2C3D4-0000-4000-8000-00000000000\(nextUUID)")!.uuid) { Data($0) }
        nextUUID += 1
        _ = uuid.withUnsafeBytes { sqlite3_bind_blob(stmt, 4, $0.baseAddress, 16, transient) }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }
}

@Suite struct NotificationDatabaseTests {
    @Test func readsNewRowsAfterTheCursor() throws {
        let fixture = try FixtureDB()
        let delivered = Date(timeIntervalSince1970: 1_800_000_000)
        fixture.add(app: "ru.keepcoder.Telegram", title: "Аня", body: "Привет! Созвон в 15?", delivered: delivered)
        // A localized field: [format, resolved, arguments].
        fixture.add(app: "com.google.Chrome", title: ["%@", "Новый заказ", ["x"]], subtitle: "shop.ru", body: "Заказ №42 оплачен")
        let db = NotificationDatabase(url: fixture.url)
        #expect(try db.latestId() == 2)
        let all = try db.notifications(after: 0)
        #expect(all.map(\.bundleId) == ["ru.keepcoder.Telegram", "com.google.Chrome"])
        #expect(all[0].title == "Аня")
        #expect(all[0].body == "Привет! Созвон в 15?")
        #expect(all[0].deliveredAt == delivered)
        #expect(all[1].title == "Новый заказ")
        #expect(all[1].subtitle == "shop.ru")
        #expect(try db.notifications(after: 1).map(\.id) == [2])
        #expect(try db.knownApps() == ["com.google.Chrome", "ru.keepcoder.Telegram"])
        #expect(all[0].uuid == "A1B2C3D4-0000-4000-8000-000000000001")
        // Read in Telegram: the app withdraws the notification, the row goes.
        fixture.exec("delete from record where rec_id = 1")
        #expect(try db.existing([1, 2, 99]) == [2])
    }

    @Test func unknownFormatIsACompatibilityError() throws {
        // macOS changed the schema: no `record` table.
        let empty = try FixtureDB(schema: false)
        #expect(throws: NotificationDatabase.Failure.self) { try NotificationDatabase(url: empty.url).latestId() }
        // Not a database at all.
        let broken = try FixtureDB(schema: false)
        try Data("garbage, not sqlite".utf8).write(to: broken.url)
        do {
            _ = try NotificationDatabase(url: broken.url).latestId()
            Issue.record("read a broken file")
        } catch let failure as NotificationDatabase.Failure {
            guard case .incompatible = failure else { Issue.record("wrong failure \(failure)"); return }
            #expect(failure.errorDescription?.contains("Несовместимая версия macOS") == true)
        }
    }

    @Test func missingFileInAReadableFolderIsIncompatible() throws {
        let fixture = try FixtureDB()
        let db = NotificationDatabase(url: fixture.dir.appendingPathComponent("moved/db"))
        #expect(throws: NotificationDatabase.Failure.noAccess) { try db.latestId() }  // folder unreadable (absent)
        let sibling = NotificationDatabase(url: fixture.dir.appendingPathComponent("db-renamed"))
        #expect(throws: NotificationDatabase.Failure.incompatible("нет файла базы")) { try sibling.latestId() }
    }

    @Test func watcherDeliversOnlyWhatIsNew() throws {
        let fixture = try FixtureDB()
        fixture.add(app: "ru.keepcoder.Telegram", title: "Старое", body: "до запуска")
        let received = Locked<[String]>([])
        let watcher = NotificationWatcher(database: NotificationDatabase(url: fixture.url)) { result in
            if case .success(let list) = result { received.mutate { $0 += list.compactMap(\.title) } }
        }
        try watcher.start()
        defer { watcher.stop() }
        watcher.check()
        #expect(received.value.isEmpty)
        fixture.add(app: "ru.keepcoder.Telegram", title: "Новое", body: "после")
        watcher.check()
        watcher.check()
        #expect(received.value == ["Новое"])
    }
}

@MainActor
@Suite struct MirrorDecisionTests {
    let telegram = MirroredNotification(id: 1, bundleId: "ru.keepcoder.Telegram", title: "Аня", subtitle: nil,
                                        body: "Созвон в 15?", deliveredAt: Date())
    let site = MirroredNotification(id: 2, bundleId: "com.google.Chrome", title: "Новый заказ", subtitle: "shop.ru",
                                    body: "Заказ №42", deliveredAt: Date())

    func decide(_ n: MirroredNotification, apps: Set<String> = ["ru.keepcoder.Telegram", "com.google.Chrome"],
                hide: Bool = false, quiet: Bool = true, focus: Bool = false) -> MirrorDecision {
        MirrorDecision.decide(n, apps: apps, hideText: hide, quietInFocus: quiet, focusOn: focus, appName: "App")
    }

    @Test func decisions() {
        #expect(decide(telegram) == .preview(title: "Аня", text: "Созвон в 15?"))
        #expect(decide(site) == .preview(title: "Новый заказ", text: "shop.ru — Заказ №42"))
        #expect(decide(telegram, apps: ["com.apple.Safari"]) == .ignore)
        // The database lowercases ids: "ru.keepcoder.telegram" is Telegram.
        let lower = MirroredNotification(id: 3, bundleId: "ru.keepcoder.telegram", title: "Аня", subtitle: nil,
                                         body: "Привет", deliveredAt: Date())
        #expect(decide(lower) == .preview(title: "Аня", text: "Привет"))
        #expect(decide(telegram, hide: true) == .preview(title: "Аня", text: "Новое уведомление"))
        #expect(decide(site, hide: true) == .preview(title: "Новый заказ", text: "App · shop.ru"))
        #expect(decide(telegram, focus: true) == .collect)
        #expect(decide(telegram, quiet: false, focus: true) == .preview(title: "Аня", text: "Созвон в 15?"))
    }

    @Test func suppressedAppsAreNotMirrored() {
        let reminder = MirroredNotification(id: 4, bundleId: "com.apple.remindd", title: "Созвон с бухгалтером", subtitle: nil,
                                            body: nil, deliveredAt: Date())
        let apps: Set<String> = ["com.apple.remindd", "ru.keepcoder.Telegram"]
        #expect(MirrorDecision.decide(reminder, apps: apps, hideText: false, quietInFocus: false, focusOn: false, appName: "Напоминания")
                == .preview(title: "Созвон с бухгалтером", text: "Напоминания"))
        // Case does not matter, as for `apps`.
        #expect(MirrorDecision.decide(reminder, apps: apps, suppressed: ["com.apple.Remindd"], hideText: false,
                                      quietInFocus: false, focusOn: false, appName: "Напоминания") == .ignore)
        #expect(MirrorDecision.decide(telegram, apps: apps, suppressed: ["com.apple.remindd"], hideText: false,
                                      quietInFocus: false, focusOn: false, appName: "App") == .preview(title: "Аня", text: "Созвон в 15?"))
    }

    @Test func settingsDefaultsAndPersistence() throws {
        let defaults = try #require(UserDefaults(suiteName: "mely-mirror-\(UUID().uuidString)"))
        let settings = NotificationMirrorSettings(defaults: defaults, installed: { $0 == "ru.keepcoder.Telegram" })
        #expect(settings.apps == ["ru.keepcoder.Telegram"])
        #expect(settings.quietInFocus)
        settings.apps.insert("com.google.Chrome")
        settings.hideText = true
        let again = NotificationMirrorSettings(defaults: defaults)
        #expect(again.apps == ["ru.keepcoder.Telegram", "com.google.Chrome"])
        #expect(again.hideText)
    }

    @Test func telemostAndTheFixedMessengerIdComeToOldLists() throws {
        let defaults = try #require(UserDefaults(suiteName: "mely-mirror-\(UUID().uuidString)"))
        defaults.set(["apps": ["ru.keepcoder.Telegram", "ru.yandex.messenger"], "hideText": false, "quietInFocus": true],
                     forKey: "notificationMirror")
        let settings = NotificationMirrorSettings(defaults: defaults, installed: { _ in true })
        #expect(settings.apps == ["ru.keepcoder.Telegram", "ru.yandex.yamb", "ru.yandex.desktop.telemost"])
        // Once: switched off afterwards, Telemost stays off.
        settings.apps.remove("ru.yandex.desktop.telemost")
        let again = NotificationMirrorSettings(defaults: defaults, installed: { _ in true })
        #expect(!again.apps.contains("ru.yandex.desktop.telemost"))
        // A new install has Telemost on when it is there.
        let fresh = try #require(UserDefaults(suiteName: "mely-mirror-\(UUID().uuidString)"))
        #expect(NotificationMirrorSettings(defaults: fresh, installed: { $0 == "ru.yandex.desktop.telemost" }).apps
                == ["ru.yandex.desktop.telemost"])
    }

    @Test func focusFromAssertions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mely-focus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Assertions.json")
        try Data(#"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.default"}}]}]}"#.utf8).write(to: file)
        #expect(SystemFocus.isOn(url: file))
        try Data(#"{"data":[{}]}"#.utf8).write(to: file)
        #expect(!SystemFocus.isOn(url: file))
        #expect(!SystemFocus.isOn(url: dir.appendingPathComponent("missing.json")))
    }
}

/// A value shared with a background callback in tests.
final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.withLock { stored } }
    func mutate(_ change: (inout T) -> Void) { lock.withLock { change(&stored) } }
}
