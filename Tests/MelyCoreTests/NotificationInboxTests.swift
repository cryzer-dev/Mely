import Testing
import Foundation
@testable import MelyCore

@MainActor
@Suite struct NotificationInboxTests {
    private func note(_ id: Int64, _ title: String = "") -> MirroredNotification {
        MirroredNotification(id: id, bundleId: "ru.keepcoder.Telegram", title: title, subtitle: nil, body: nil, deliveredAt: Date())
    }

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mely-inbox-\(UUID().uuidString)")
            .appendingPathComponent("notifications.json")
    }

    @Test func keepsTheLatestAndCountsUnseen() {
        let inbox = NotificationInbox()
        for i in 1...35 { inbox.add(note(Int64(i)), appName: "Telegram", title: "\(i)", text: "") }
        #expect(inbox.items.count == NotificationInbox.keep)
        #expect(inbox.items.first?.title == "35")
        #expect(inbox.unseen == 35)
        inbox.markSeen()
        #expect(inbox.unseen == 0)
        inbox.keepApps(only: [35, 34])
        #expect(inbox.items.map(\.id) == ["nc-35", "nc-34"])
        inbox.remove("nc-35")
        #expect(inbox.items.map(\.id) == ["nc-34"])
    }

    @Test func calendarNewsLivesByItsEvent() {
        let inbox = NotificationInbox()
        let now = Date()
        inbox.add(note(1), appName: "Telegram", title: "Аня", text: "Привет")
        inbox.addCalendar(eventId: "groom", symbol: "calendar.badge.clock", title: "Перенесено: 14:00 → 15:30", text: "Груминг",
                          ends: now.addingTimeInterval(3600))
        inbox.addCalendar(eventId: "lunch", symbol: "calendar.badge.plus", title: "Новое событие · 13:00", text: "Обед",
                          ends: now.addingTimeInterval(60))
        #expect(inbox.unseen == 3)
        // Notification Center no longer has the message: only it goes.
        inbox.keepApps(only: [])
        #expect(inbox.items.map(\.id) == ["cal-lunch", "cal-groom"])
        // Moved again: one entry, on top.
        inbox.addCalendar(eventId: "groom", symbol: "calendar.badge.clock", title: "Перенесено: 14:00 → 16:00", text: "Груминг",
                          ends: now.addingTimeInterval(7200))
        #expect(inbox.items.map(\.title) == ["Перенесено: 14:00 → 16:00", "Новое событие · 13:00"])
        #expect(inbox.unseen == 2)
        // Lunch is over.
        inbox.dropEnded(now: now.addingTimeInterval(120))
        #expect(inbox.items.map(\.id) == ["cal-groom"])
        #expect(inbox.unseen == 1)
    }

    @Test func removesOneSource() {
        let inbox = NotificationInbox()
        inbox.add(note(1), appName: "Telegram", title: "Аня", text: "")
        inbox.addCalendar(eventId: "e", symbol: "calendar", title: "Новое событие", text: "Обед", ends: .distantFuture)
        inbox.removeCalendar()
        #expect(inbox.items.map(\.id) == ["nc-1"])
        inbox.addCalendar(eventId: "e", symbol: "calendar", title: "Новое событие", text: "Обед", ends: .distantFuture)
        inbox.removeApps()
        #expect(inbox.items.map(\.id) == ["cal-e"])
    }

    @Test func survivesARestart() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let inbox = NotificationInbox(fileURL: url)
        inbox.add(note(1), appName: "Telegram", title: "Аня", text: "Созвон в 15:30")
        inbox.addCalendar(eventId: "g", symbol: "calendar.badge.clock", title: "Перенесено", text: "Груминг", ends: .distantFuture)
        inbox.saveNow()
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)

        let again = NotificationInbox(fileURL: url)
        #expect(again.items == inbox.items)
        #expect(again.unseen == 2)
        again.clear()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(NotificationInbox(fileURL: url).items.isEmpty)
    }

    @Test func garbageFileStartsEmpty() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(NotificationInbox(fileURL: url).items.isEmpty)
    }

    @Test func notPersistingDeletesTheFile() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let inbox = NotificationInbox(fileURL: url)
        inbox.add(note(1), appName: "Telegram", title: "Аня", text: "")
        inbox.saveNow()
        #expect(FileManager.default.fileExists(atPath: url.path))
        inbox.fileURL = nil
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(inbox.items.count == 1)
    }

    @Test func settingsDefaultsAndApplying() throws {
        let defaults = try #require(UserDefaults(suiteName: "mely-inbox-\(UUID().uuidString)"))
        let settings = InboxSettings(defaults: defaults)
        #expect(settings.keepsMessages && settings.keepsCalendar && settings.persists)
        var told = 0
        settings.changed = { told += 1 }
        settings.keepsCalendar = false
        settings.persists = false
        #expect(told == 2)
        let again = InboxSettings(defaults: defaults)
        #expect(again.keepsMessages && !again.keepsCalendar && !again.persists)

        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let inbox = NotificationInbox(fileURL: url)
        inbox.add(note(1), appName: "Telegram", title: "Аня", text: "")
        inbox.addCalendar(eventId: "e", symbol: "calendar", title: "Новое событие", text: "Обед", ends: .distantFuture)
        inbox.saveNow()
        inbox.apply(again, fileURL: url)
        #expect(inbox.items.map(\.id) == ["nc-1"])
        #expect(inbox.fileURL == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
