import Foundation
import SQLite3

/// One notification macOS delivered, as the Notification Center database keeps it.
public struct MirroredNotification: Identifiable, Equatable, Sendable {
    /// `record.rec_id`: grows with every new notification.
    public let id: Int64
    /// The notification's identifier in Notification Center (its AXIdentifier there).
    public let uuid: String?
    public let bundleId: String
    public let title: String?
    public let subtitle: String?
    public let body: String?
    public let deliveredAt: Date

    public init(id: Int64, uuid: String? = nil, bundleId: String, title: String?, subtitle: String?, body: String?,
                deliveredAt: Date) {
        self.id = id
        self.uuid = uuid
        self.bundleId = bundleId
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.deliveredAt = deliveredAt
    }
}

/// The record's `data` column: a binary plist whose `req` holds `titl`, `subt` and `body`
/// (approach checked in nonja on macOS 26).
public enum NotificationPayload {
    public struct Fields: Equatable, Sendable {
        public var app: String?
        public var title: String?
        public var subtitle: String?
        public var body: String?
    }

    public static func parse(_ data: Data) -> Fields? {
        guard let root = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        else { return nil }
        let req = root["req"] as? [String: Any] ?? [:]
        return Fields(app: root["app"] as? String, title: string(req["titl"]),
                      subtitle: string(req["subt"]), body: string(req["body"]))
    }

    /// A text field is either a string or a localized `[format, resolved, arguments]` array:
    /// the resolved text first, the format otherwise.
    static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s.isEmpty ? nil : s }
        guard let array = value as? [Any] else { return nil }
        for candidate in [array.count > 1 ? array[1] : nil, array.first] {
            if let s = candidate as? String, !s.isEmpty { return s }
        }
        return nil
    }
}

/// The Notification Center database (`usernoted`), read only. Needs Full Disk Access.
public struct NotificationDatabase: Sendable {
    public static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
    /// Apple's reference date (2001-01-01) in Unix time.
    static let appleEpochOffset: TimeInterval = 978_307_200

    public enum Failure: Error, Equatable, LocalizedError {
        /// No Full Disk Access (or the folder moved).
        case noAccess
        /// The file is there but is not the database we know: macOS changed it.
        case incompatible(String)

        public var errorDescription: String? {
            switch self {
            case .noAccess: "Нет доступа к базе уведомлений: нужен «Доступ к диску»"
            case .incompatible: "Несовместимая версия macOS: не удаётся прочитать уведомления"
            }
        }
    }

    public let url: URL

    public init(url: URL = NotificationDatabase.defaultURL) {
        self.url = url
    }

    /// The newest `rec_id`: where mirroring starts, so old notifications are not replayed.
    public func latestId() throws -> Int64 {
        try query("select coalesce(max(rec_id), 0) from record") { stmt in sqlite3_column_int64(stmt, 0) }.first ?? 0
    }

    /// Notifications after `cursor`, oldest first.
    public func notifications(after cursor: Int64, limit: Int = 50) throws -> [MirroredNotification] {
        let sql = """
            select r.rec_id, r.data, r.delivered_date, a.identifier, r.uuid
            from record r left join app a on a.app_id = r.app_id
            where r.rec_id > ?1 order by r.rec_id limit ?2
            """
        return try query(sql, bind: { stmt in
            sqlite3_bind_int64(stmt, 1, cursor)
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }) { stmt -> MirroredNotification? in
            let id = sqlite3_column_int64(stmt, 0)
            guard let data = Self.blob(stmt, 1), let fields = NotificationPayload.parse(data),
                  let bundleId = Self.text(stmt, 3) ?? fields.app else { return nil }
            let delivered = sqlite3_column_type(stmt, 2) == SQLITE_NULL
                ? Date() : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2) + Self.appleEpochOffset)
            return MirroredNotification(id: id, uuid: Self.blob(stmt, 4).flatMap(Self.uuidString), bundleId: bundleId,
                                        title: fields.title,
                                        subtitle: fields.subtitle, body: fields.body, deliveredAt: delivered)
        }.compactMap { $0 }
    }

    /// Which of `ids` are still in Notification Center. A notification leaves it when the
    /// user reads the chat (the app withdraws it) or dismisses it.
    public func existing(_ ids: [Int64]) throws -> Set<Int64> {
        guard !ids.isEmpty else { return [] }
        let list = ids.map(String.init).joined(separator: ",")
        return Set(try query("select rec_id from record where rec_id in (\(list))") { stmt in sqlite3_column_int64(stmt, 0) })
    }

    /// Apps that have notifications in the database now: candidates for the app list.
    public func knownApps() throws -> [String] {
        try query("select identifier from app where identifier is not null order by identifier") { stmt in
            Self.text(stmt, 0)
        }.compactMap { $0 }
    }

    /// Opens, runs, closes: the file is someone else's and changes under us, so no
    /// connection is kept. `mode=ro`, not `immutable`: fresh rows sit in the WAL.
    private func query<T>(_ sql: String, bind: (OpaquePointer) -> Void = { _ in },
                          row: (OpaquePointer) -> T) throws -> [T] {
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: url.path) else {
            // Without Full Disk Access even the folder is unreadable; a readable folder
            // without the file means macOS keeps notifications elsewhere now.
            let folderReadable = fm.isReadableFile(atPath: url.deletingLastPathComponent().path)
            throw folderReadable && !fm.fileExists(atPath: url.path) ? Failure.incompatible("нет файла базы") : Failure.noAccess
        }
        var db: OpaquePointer?
        let uri = "file:\(url.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open"
            sqlite3_close(db)
            throw message.contains("authoriz") || message.contains("permission") ? Failure.noAccess : Failure.incompatible(message)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            // "no such table / column", "file is not a database": the format changed.
            throw Failure.incompatible(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        var out: [T] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW { out.append(row(stmt)); continue }
            if step == SQLITE_DONE { break }
            throw Failure.incompatible(String(cString: sqlite3_errmsg(db)))
        }
        return out
    }

    private static func blob(_ stmt: OpaquePointer, _ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return count > 0 ? Data(bytes: bytes, count: count) : nil
    }

    /// The 16 raw bytes as Notification Center writes the identifier (uppercase).
    static func uuidString(_ data: Data) -> String? {
        guard data.count == 16 else { return nil }
        let b = [UInt8](data)
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])).uuidString
    }

    private static func text(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        let s = String(cString: c)
        return s.isEmpty ? nil : s
    }
}
