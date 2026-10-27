import AppKit
import SwiftUI
import EventKit
import Observation
import OSLog
import MelyCore
import MelyUI

private let log = Logger(subsystem: "dev.mely.app", category: "calendar")

/// Today's events from the macOS calendars (Yandex through CalDAV, Google, iCloud…):
/// the "Сегодня" tab, news about new and moved events, reminders with «Подключиться».
@MainActor
@Observable
final class CalendarIntegration: Integration {
    let id = "calendar"
    let displayName = "Календарь"
    let summary = "События на сегодня, новые встречи и напоминания с «Подключиться»"
    let requiredPermissions: [SystemPermission] = [.calendars]
    private(set) var status: IntegrationStatus = .off
    /// Nil while off or without access.
    private(set) var agenda: Agenda?

    @ObservationIgnored let settings = CalendarSettings()
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var snapshot = EventSnapshot()
    @ObservationIgnored private var reminders = ReminderSchedule()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var settingsWindow: NSWindow?
    /// Today and tomorrow, for the snapshot and the reminders.
    @ObservationIgnored private var upcoming: [CalendarEvent] = []
    /// Previews under the notch; meeting reminders carry «Подключиться».
    @ObservationIgnored var peek: ((PeekContent) -> Void)?
    /// The "Уведомления" tab, shared with the mirrored notifications; what of it is kept.
    @ObservationIgnored var inbox: NotificationInbox?
    @ObservationIgnored var inboxSettings: InboxSettings?
    /// Joins pending on a reminder's button, by preview id.
    @ObservationIgnored private var pendingJoins: [String: MeetingLink] = [:]

    var actions: [IntegrationAction] {
        guard status != .off else { return [] }
        return [IntegrationAction(id: "settings", title: "Календари…") { [weak self] in self?.showSettings() }]
    }

    func start() async {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            status = .needsPermission(.calendars)
            // Granted later in System Settings: try again on the next tick.
            scheduleTimer()
            return
        }
        status = .running
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleReload() }
            }
        }
        reload(announce: false)
        scheduleTimer()
    }

    func stop() async {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        timer?.invalidate(); timer = nil
        reloadTask?.cancel()
        agenda = nil
        snapshot = EventSnapshot()
        inbox?.removeCalendar()
        status = .off
    }

    /// Every 30 s: reminders come due, the day rolls over, access may have been granted.
    private func scheduleTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.status == .needsPermission(.calendars) {
                    if EKEventStore.authorizationStatus(for: .event) == .fullAccess { Task { await self.start() } }
                    return
                }
                self.reload(announce: true)
            }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Changes come in bursts while CalDAV syncs: read once they settle.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.reload(announce: true)
        }
    }

    private func reload(announce: Bool) {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today),
              let after = cal.date(byAdding: .day, value: 2, to: today) else { return }
        let calendars = store.calendars(for: .event).filter { !settings.hiddenCalendars.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { agenda = Agenda(today: [], tomorrow: []); return }
        let predicate = store.predicateForEvents(withStart: today, end: after, calendars: calendars)
        let events = store.events(matching: predicate).map(Self.event)
        let todays = events.filter { $0.start < tomorrow && $0.end > today }
        let tomorrows = events.filter { $0.start >= tomorrow }
        agenda = Agenda(today: todays, tomorrow: tomorrows)
        upcoming = events

        let changes = snapshot.update(events)
        if announce { tell(changes) }
        inbox?.dropEnded(now: now)
        for event in reminders.due(events, minutes: settings.reminderMinutes, now: now) { remind(event, now: now) }
    }

    private func tell(_ changes: EventChanges) {
        for event in changes.added.prefix(3) {
            log.info("new event")
            news(PeekContent(id: "event-new-\(event.id)", symbol: "calendar.badge.plus", tint: .blue,
                             title: "Новое событие · \(Self.time(event.start))", subtitle: event.title), event: event)
        }
        for move in changes.moved.prefix(3) {
            log.info("moved event")
            news(PeekContent(id: "event-moved-\(move.event.id)", symbol: "calendar.badge.clock", tint: .orange,
                             title: "Перенесено: \(Self.time(move.oldStart)) → \(Self.time(move.event.start))",
                             subtitle: move.event.title), event: move.event)
        }
    }

    /// Under the notch, and into the "Уведомления" tab until the event is over.
    private func news(_ content: PeekContent, event: CalendarEvent) {
        peek?(content)
        guard inboxSettings?.keepsCalendar ?? true else { return }
        inbox?.addCalendar(eventId: event.id, symbol: content.symbol, title: content.title, text: content.subtitle, ends: event.end)
    }

    private func remind(_ event: CalendarEvent, now: Date) {
        let id = "event-soon-\(event.id)"
        if let meeting = event.meeting { pendingJoins[id] = meeting }
        log.info("reminder")
        // The title counts down by itself ("· через 4 мин", then "· идёт 12 мин"); it stays
        // until «×», «Подключиться» or the event's end.
        peek?(PeekContent(id: id, symbol: "video.fill", tint: .green, title: event.title,
                          subtitle: event.meeting.map { $0.service == .other ? "Встреча · \($0.name)" : "Встреча в \($0.name)" }
                              ?? (event.location ?? Self.time(event.start)),
                          appBundleId: event.meeting?.service.appBundleId,
                          actionTitle: event.meeting?.actionTitle, until: event.start,
                          staysUntil: event.end))
    }

    /// A reminder is gone (closed, joined, over): its join is not needed any more.
    func forgetPeek(_ id: String) {
        pendingJoins.removeValue(forKey: id)
    }

    /// The reminder's button.
    func runPeekAction(_ id: String) {
        guard let link = pendingJoins.removeValue(forKey: id) else { return }
        join(link)
    }

    /// «Подключиться»: the service's app when installed and chosen, else the browser;
    /// «Открыть ссылку» (a site Mely does not know): always the browser.
    func join(_ link: MeetingLink) {
        let workspace = NSWorkspace.shared
        guard settings.opensInApp(link.service), let id = link.service.appBundleId,
              let app = workspace.urlForApplication(withBundleIdentifier: id) else {
            workspace.open(link.url)
            return
        }
        if let direct = link.appURL {
            workspace.open(direct)
            return
        }
        // Telemost takes the https link as a document; in case it only opens, the link is
        // on the clipboard and the notch says where to paste it.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
        workspace.open([link.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        peek?(PeekContent(id: "join-hint", symbol: "doc.on.clipboard", tint: .gray, title: "Ссылка на встречу скопирована",
                          subtitle: "Если \(link.service.title) не открыл встречу: Подключиться → ⌘V", appBundleId: id))
    }

    /// The meeting to join by voice or hotkey: the running one or the next within 15 min.
    func joinNow() -> Bool {
        guard let event = agenda?.joinable(now: Date()), let link = event.meeting else { return false }
        join(link)
        return true
    }

    static func event(_ e: EKEvent) -> CalendarEvent {
        let occurrence = e.occurrenceDate ?? e.startDate ?? Date()
        return CalendarEvent(id: "\(e.eventIdentifier ?? e.calendarItemIdentifier)@\(Int(occurrence.timeIntervalSince1970))",
                             title: e.title?.isEmpty == false ? e.title! : "Без названия",
                             start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                             location: e.location?.isEmpty == false ? e.location : nil,
                             calendarTitle: e.calendar.title,
                             meeting: MeetingLink.find(url: e.url, location: e.location, notes: e.notes))
    }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    func showSettings() {
        settingsWindow?.close()
        let calendars = store.calendars(for: .event).map {
            CalendarSettingsView.CalendarItem(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title)
        }
        let hasYandex = store.sources.contains {
            let t = $0.title.lowercased()
            return t.contains("yandex") || t.contains("яндекс")
        }
        let view = CalendarSettingsView(
            settings: settings, calendars: calendars, hasYandex: hasYandex,
            openAccounts: { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!) },
            close: { [weak self] in
                self?.settingsWindow?.close()
                self?.settingsWindow = nil
                self?.reload(announce: false)
            })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Mely — календарь"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
