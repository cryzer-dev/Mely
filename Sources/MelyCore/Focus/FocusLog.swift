import Foundation
import Observation
import os

private let focusLog = Logger(subsystem: "dev.mely.app", category: "focus")

/// One focus session in the log: the time actually worked, without pauses or the tail after the end.
public struct FocusRecord: Codable, Equatable, Identifiable, Sendable {
    /// The session's id: a session extended after its end rewrites its record.
    public let id: String
    public let taskId: String?
    public let taskTitle: String?
    public let start: Date
    public let worked: TimeInterval

    public init(id: String, taskId: String? = nil, taskTitle: String? = nil, start: Date, worked: TimeInterval) {
        self.id = id
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.start = start
        self.worked = worked
    }
}

/// The sessions on this Mac, `~/Library/Application Support/Mely/focus-log.json`.
/// Never sent anywhere; kept while the integration is off.
@MainActor
@Observable
public final class FocusLog {
    public private(set) var records: [FocusRecord] = []
    @ObservationIgnored private let fileURL: URL?

    /// Shorter sessions are not kept.
    public static let minimum: TimeInterval = 60
    /// Older records go at launch.
    public static let keepDays = 400

    /// Loads the file and drops what is older than `keepDays`; nil `fileURL` keeps it in memory.
    public init(fileURL: URL? = FocusLog.defaultURL, now: Date = Date()) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            records = (try? JSONDecoder().decode([FocusRecord].self, from: data)) ?? []
        }
        let cutoff = now.addingTimeInterval(-TimeInterval(Self.keepDays) * 86_400)
        let kept = records.filter { $0.start >= cutoff }
        if kept.count != records.count {
            records = kept
            save()
        }
    }

    /// Appends the session, or rewrites it when it was extended after its end.
    public func add(_ record: FocusRecord) {
        guard record.worked >= Self.minimum else { return }
        if let i = records.firstIndex(where: { $0.id == record.id }) {
            records[i] = record
        } else {
            records.append(record)
        }
        save()
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            focusLog.error("cannot save the focus log: \(error.localizedDescription, privacy: .public)")
        }
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mely", isDirectory: true).appendingPathComponent("focus-log.json")
    }
}

/// A day's focus: «Фокус сегодня · 2 ч 10 мин · 4 сессии».
public struct FocusDay: Equatable, Sendable {
    public let worked: TimeInterval
    public let sessions: Int

    public var label: String {
        "Фокус сегодня · \(FocusStats.format(worked)) · \(sessions) \(FocusStats.sessionsWord(sessions))"
    }
}

/// Sums over the log; records of deleted tasks still count.
public enum FocusStats {
    /// Sessions started today; resets at midnight.
    public static func today(records: [FocusRecord], now: Date, calendar: Calendar = .current) -> FocusDay {
        let today = records.filter { calendar.isDate($0.start, inSameDayAs: now) }
        return FocusDay(worked: today.reduce(0) { $0 + $1.worked }, sessions: today.count)
    }

    /// All the time worked on a task.
    public static func spent(taskId: String, records: [FocusRecord]) -> TimeInterval {
        records.filter { $0.taskId == taskId }.reduce(0) { $0 + $1.worked }
    }

    /// `taskId → spent`, for the "Задачи" tab.
    public static func spentByTask(records: [FocusRecord]) -> [String: TimeInterval] {
        records.reduce(into: [:]) { sums, r in
            if let id = r.taskId { sums[id, default: 0] += r.worked }
        }
    }

    /// «ушло» is highlighted past the estimate; «1 ч+» has no upper bound to pass.
    public static func exceeds(_ estimate: TaskEstimate?, spent: TimeInterval) -> Bool {
        guard let estimate, estimate != .overHour else { return false }
        return minutes(spent) > estimate.minutes
    }

    /// «ушло 1 ч 10 мин».
    public static func spentLabel(_ spent: TimeInterval) -> String { "ушло \(format(spent))" }

    /// «40 мин», «1 ч 10 мин».
    public static func format(_ time: TimeInterval) -> String {
        TaskEstimate.format(totalMinutes: minutes(time))
    }

    static func minutes(_ time: TimeInterval) -> Int { Int((time / 60).rounded()) }

    /// «1 сессия», «3 сессии», «5 сессий».
    static func sessionsWord(_ n: Int) -> String {
        let tens = n % 100, ones = n % 10
        if (11...14).contains(tens) { return "сессий" }
        switch ones {
        case 1: return "сессия"
        case 2...4: return "сессии"
        default: return "сессий"
        }
    }
}
