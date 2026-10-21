import Foundation

/// A calendar event, copied out of EventKit so the logic stays testable.
public struct CalendarEvent: Identifiable, Equatable, Sendable {
    /// EventKit's identifier plus the occurrence's original date: one occurrence of a
    /// repeating event, and the same id after it is moved.
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    public let calendarTitle: String
    /// The call link found in the url, location or notes.
    public let meeting: MeetingLink?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, location: String? = nil,
                calendarTitle: String = "", meeting: MeetingLink? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.calendarTitle = calendarTitle
        self.meeting = meeting
    }

    public func isNow(_ now: Date) -> Bool { start <= now && now < end }
}

/// Today as the overview shows it: all-day events on top, timed ones in order, the
/// current one marked; an empty day points at tomorrow's first event.
public struct Agenda: Equatable, Sendable {
    public let allDay: [CalendarEvent]
    public let timed: [CalendarEvent]
    /// Shown under "Событий на сегодня нет".
    public let nextTomorrow: CalendarEvent?

    public var isEmpty: Bool { allDay.isEmpty && timed.isEmpty }

    public init(today: [CalendarEvent], tomorrow: [CalendarEvent]) {
        allDay = today.filter(\.isAllDay).sorted { $0.title < $1.title }
        timed = today.filter { !$0.isAllDay }.sorted { $0.start != $1.start ? $0.start < $1.start : $0.title < $1.title }
        nextTomorrow = allDay.isEmpty && timed.isEmpty
            ? tomorrow.filter { !$0.isAllDay }.min { $0.start < $1.start } ?? tomorrow.first
            : nil
    }

    /// The meeting to join now: the running one, else the next starting within `soon`.
    public func joinable(now: Date, soon: TimeInterval = 15 * 60) -> CalendarEvent? {
        let withLink = timed.filter { $0.meeting != nil }
        return withLink.first { $0.isNow(now) }
            ?? withLink.first { $0.start > now && $0.start.timeIntervalSince(now) <= soon }
    }
}

/// What changed in the calendars since the last look. The first look after launch only
/// remembers: existing events are not news.
public struct EventChanges: Equatable, Sendable {
    public struct Moved: Equatable, Sendable {
        public let event: CalendarEvent
        public let oldStart: Date
        public let oldEnd: Date
    }

    public let added: [CalendarEvent]
    public let moved: [Moved]

    public var isEmpty: Bool { added.isEmpty && moved.isEmpty }
}

public struct EventSnapshot: Sendable {
    private var known: [String: (start: Date, end: Date)]?

    public init() {}

    /// Compares `events` (today and tomorrow) with the last look and remembers them.
    /// Event ids survive a move, so a moved event is reported as moved, not as new.
    public mutating func update(_ events: [CalendarEvent]) -> EventChanges {
        let current = Dictionary(events.map { ($0.id, ($0.start, $0.end)) }, uniquingKeysWith: { a, _ in a })
        defer { known = current }
        guard let known else { return EventChanges(added: [], moved: []) }
        var added: [CalendarEvent] = []
        var moved: [EventChanges.Moved] = []
        for event in events {
            if let old = known[event.id] {
                if old.start != event.start || old.end != event.end {
                    moved.append(.init(event: event, oldStart: old.start, oldEnd: old.end))
                }
            } else {
                added.append(event)
            }
        }
        return EventChanges(added: added.sorted { $0.start < $1.start }, moved: moved)
    }
}

/// A call link in an event, and how to open it in the service's app.
public struct MeetingLink: Equatable, Sendable {
    public enum Service: String, CaseIterable, Sendable {
        case telemost, zoom, meet, teams

        public var title: String {
            switch self {
            case .telemost: "Телемост"
            case .zoom: "Zoom"
            case .meet: "Google Meet"
            case .teams: "Teams"
            }
        }

        /// The desktop app, when the service has one.
        public var appBundleId: String? {
            switch self {
            case .telemost: "ru.yandex.desktop.telemost"
            case .zoom: "us.zoom.xos"
            case .teams: "com.microsoft.teams2"
            case .meet: nil
            }
        }

        static func of(host: String) -> Service? {
            let h = host.lowercased()
            if h == "telemost.yandex.ru" || h.hasSuffix(".telemost.yandex.ru") || h == "telemost.360.yandex.ru" { return .telemost }
            if h == "zoom.us" || h.hasSuffix(".zoom.us") { return .zoom }
            if h == "meet.google.com" { return .meet }
            if h == "teams.microsoft.com" || h == "teams.live.com" { return .teams }
            return nil
        }
    }

    public let service: Service
    public let url: URL

    public init(service: Service, url: URL) {
        self.service = service
        self.url = url
    }

    /// The first call link in the event's url, then location, then notes.
    public static func find(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        if let url, let host = url.host, let service = Service.of(host: host) { return MeetingLink(service: service, url: url) }
        for text in [location, notes].compactMap({ $0 }) {
            for found in links(in: text) {
                if let host = found.host, let service = Service.of(host: host) { return MeetingLink(service: service, url: found) }
            }
        }
        return nil
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
            .filter { $0.scheme == "https" || $0.scheme == "http" }
    }

    /// The link the service's app opens directly, without a browser; nil when the app
    /// takes the https link itself (Telemost) or there is no app (Meet).
    public var appURL: URL? {
        switch service {
        case .zoom:
            // https://…zoom.us/j/<id>?pwd=… → zoommtg://zoom.us/join?confno=<id>&pwd=…
            let parts = url.pathComponents
            guard let j = parts.firstIndex(where: { $0 == "j" || $0 == "w" }), j + 1 < parts.count else { return nil }
            var c = URLComponents()
            c.scheme = "zoommtg"
            c.host = "zoom.us"
            c.path = "/join"
            var items = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: parts[j + 1])]
            if let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pwd" })?.value {
                items.append(URLQueryItem(name: "pwd", value: pwd))
            }
            c.queryItems = items
            return c.url
        case .teams:
            // https://teams.microsoft.com/l/meetup-join/… → msteams:/l/meetup-join/…
            let s = url.absoluteString
            guard let range = s.range(of: "/l/") else { return nil }
            return URL(string: "msteams:" + s[range.lowerBound...])
        case .telemost, .meet:
            return nil
        }
    }
}

/// The live "через 4 мин" of a meeting reminder (task 4.6): it stays until the meeting starts.
public enum MeetingCountdown {
    /// Whole minutes left, rounded up, so "через 1 мин" lasts the whole last minute.
    public static func text(until start: Date, now: Date) -> String {
        let seconds = start.timeIntervalSince(now)
        guard seconds > 0 else { return "сейчас" }
        return "через \(Int((seconds / 60).rounded(.up))) мин"
    }

    /// Whether the reminder is still worth showing.
    public static func isActive(until start: Date, now: Date) -> Bool { now < start }
}
