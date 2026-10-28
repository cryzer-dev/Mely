import Foundation

/// A task as typed in «+ Задача», before it is saved.
public struct QuickTask: Equatable, Sendable {
    public var title: String
    public var due: TaskDue?
    public var priority: TaskPriority
    public var tags: [String]
    public var estimate: TaskEstimate?
    /// Nil: the list for new tasks from Settings.
    public var listId: String?

    public init(title: String, due: TaskDue? = nil, priority: TaskPriority = .none, tags: [String] = [],
                estimate: TaskEstimate? = nil, listId: String? = nil) {
        self.title = title
        self.due = due
        self.priority = priority
        self.tags = tags
        self.estimate = estimate
        self.listId = listId
    }
}

/// Reads «позвонить в банк завтра в 10 !! #работа ~45м» on the device: due day and time,
/// priority, tags, estimate. What it recognizes is cut out of the title.
public enum QuickTaskParser {
    /// What a piece of the text sets.
    public enum Field: Hashable, Sendable {
        case due, priority, tag, estimate
    }

    /// A recognized piece of the text.
    public struct Token: Equatable, Sendable {
        public let field: Field
        public let range: Range<String.Index>
        let value: Value
    }

    enum Value: Equatable, Sendable {
        case day(offset: Int)
        case weekday(Int)              // Calendar weekday: 1 Sunday … 7 Saturday
        case date(day: Int, month: Int, year: Int?)
        case time(hour: Int, minute: Int, part: DayPart?)
        case after(minutes: Int)
        case priority(TaskPriority)
        case tag(String)
        case estimate(TaskEstimate)
    }

    enum DayPart: String, Sendable { case morning = "утра", afternoon = "дня", evening = "вечера", night = "ночи" }

    public static func parse(_ text: String, now: Date, calendar: Calendar = .current) -> QuickTask {
        let tokens = tokens(in: text)
        var task = QuickTask(title: title(text, without: tokens.map(\.range)))
        for token in tokens {
            switch token.value {
            case let .priority(p): task.priority = p
            case let .tag(t): task.tags.append(t)
            case let .estimate(e): task.estimate = e
            default: break
            }
        }
        task.tags = TaskMarks(tags: task.tags).tags
        task.due = due(tokens.filter { $0.field == .due }.map(\.value), now: now, calendar: calendar)
        return task
    }

    /// The recognized pieces, in text order. Single-valued fields keep their last match;
    /// earlier ones stay in the title.
    public static func tokens(in text: String) -> [Token] {
        var found: [Token] = []
        func free(_ r: Range<String.Index>) -> Bool { !found.contains { $0.range.overlaps(r) } }
        func scan(_ rule: Rule, all: Bool = false) {
            var matches: [Token] = []
            for m in rule.regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(m.range, in: text), free(r) else { continue }
                let groups = (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } }
                if let value = rule.read(groups) { matches.append(Token(field: rule.field, range: r, value: value)) }
            }
            // Matches are in text order, so the last one is the rightmost.
            found += all ? matches : Array(matches.suffix(1))
        }
        scan(Rules.estimate)
        scan(Rules.tag, all: true)
        scan(Rules.priority)
        scan(Rules.after)
        // Every day and time first, so «в 12» never takes the 12 of «12 ноября»…
        for rule in [Rules.numericDate, Rules.monthDate, Rules.dayWord, Rules.weekday, Rules.time, Rules.clock] {
            scan(rule, all: true)
        }
        // …then one day and one time: the last of each wins.
        func isTime(_ t: Token) -> Bool { if case .time = t.value { true } else { false } }
        func isDay(_ t: Token) -> Bool {
            switch t.value {
            case .day, .weekday, .date: true
            default: false
            }
        }
        let lastDay = found.last(where: isDay)?.range
        let lastTime = found.last(where: isTime)?.range
        found.removeAll { (isDay($0) && $0.range != lastDay) || (isTime($0) && $0.range != lastTime) }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// The text without the recognized pieces, spaces collapsed, first letter capitalized.
    static func title(_ text: String, without ranges: [Range<String.Index>]) -> String {
        let cleaned = removing(ranges, from: text)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;")))
        guard let first = cleaned.first else { return "" }
        return first.uppercased() + cleaned.dropFirst()
    }

    /// The text with these pieces cut out and runs of spaces collapsed.
    public static func removing(_ ranges: [Range<String.Index>], from text: String) -> String {
        var result = ""
        var cursor = text.startIndex
        for r in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) where r.lowerBound >= cursor {
            result += text[cursor..<r.lowerBound]
            cursor = r.upperBound
        }
        result += text[cursor...]
        return result.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Due

    static func due(_ values: [Value], now: Date, calendar: Calendar) -> TaskDue? {
        let today = calendar.startOfDay(for: now)
        var day: Date?
        var time: (hour: Int, minute: Int, part: DayPart?)?
        for value in values {
            switch value {
            case let .after(minutes):
                let date = now.addingTimeInterval(TimeInterval(minutes * 60))
                return .time(calendar.date(bySetting: .second, value: 0, of: date) ?? date)
            case let .day(offset):
                day = calendar.date(byAdding: .day, value: offset, to: today)
            case let .weekday(target):
                let current = calendar.component(.weekday, from: today)
                let ahead = (target - current + 7) % 7
                day = calendar.date(byAdding: .day, value: ahead == 0 ? 7 : ahead, to: today)
            case let .date(d, m, y):
                day = date(day: d, month: m, year: y, today: today, calendar: calendar)
            case let .time(h, m, part):
                time = (h, m, part)
            default: break
            }
        }
        guard let time else { return day.map { .day(of: $0, calendar: calendar) } }
        let hour = hour(time.hour, part: time.part)
        if let day {
            return calendar.date(bySettingHour: hour, minute: time.minute, second: 0, of: day).map(TaskDue.time)
        }
        // No day: today, or the evening when "в 9" is past but 21:00 is not, else tomorrow.
        func at(_ h: Int, _ d: Date) -> Date? { calendar.date(bySettingHour: h, minute: time.minute, second: 0, of: d) }
        guard let todays = at(hour, today) else { return nil }
        if todays > now { return .time(todays) }
        if time.part == nil, hour < 12, let evening = at(hour + 12, today), evening > now { return .time(evening) }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return at(hour, tomorrow).map(TaskDue.time)
    }

    static func hour(_ h: Int, part: DayPart?) -> Int {
        switch part {
        case .morning: h == 12 ? 0 : h
        case .afternoon, .evening: h < 12 ? h + 12 : h
        case .night: h == 12 ? 0 : h
        case nil: h
        }
    }

    /// A day and month without a year: this year, or the next one once it has passed.
    static func date(day: Int, month: Int, year: Int?, today: Date, calendar: Calendar) -> Date? {
        if let year {
            let full = year < 100 ? 2000 + year : year
            return calendar.date(from: DateComponents(year: full, month: month, day: day))
        }
        let thisYear = calendar.component(.year, from: today)
        guard let date = calendar.date(from: DateComponents(year: thisYear, month: month, day: day)) else { return nil }
        return date < today ? calendar.date(byAdding: .year, value: 1, to: date) : date
    }

    // MARK: - Rules

    struct Rule: Sendable {
        let field: Field
        let regex: NSRegularExpression
        let read: @Sendable ([String?]) -> Value?

        init(_ field: Field, _ pattern: String, read: @escaping @Sendable ([String?]) -> Value?) {
            self.field = field
            // Whole words only: no letter or digit right before or after.
            regex = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])"# + pattern + #"(?![\p{L}\p{N}])"#,
                                             options: [.caseInsensitive])
            self.read = read
        }
    }

    enum Rules {
        static let estimate = Rule(.estimate, TaskMarks.estimatePattern) { g in
            TaskMarks.estimate(number: g[1], unit: g[2], extra: g[3], plus: g[4] != nil).map(Value.estimate)
        }
        static let tag = Rule(.tag, #"#([\p{L}\p{N}_-]+)"#) { g in g[1].map(Value.tag) }
        static let priority = Rule(.priority, #"(?<!!)(!{1,3})(?!!)"#) { g in
            TaskPriority(rawValue: g[1]?.count ?? 0).map(Value.priority)
        }
        static let after = Rule(.due, #"через\s+(?:(\d+)\s*)?(минут[уы]?|мин|час(?:а|ов)?|ч|д(?:ень|ня|ней)|дн)"#) { g in
            let n = g[1].flatMap(Int.init) ?? 1
            guard n > 0, let unit = g[2]?.lowercased() else { return nil }
            if unit.hasPrefix("м") { return .after(minutes: n) }
            if unit.hasPrefix("ч") { return .after(minutes: n * 60) }
            return .day(offset: n)
        }
        static let dayWord = Rule(.due, #"(?:(?:на|к)\s+)?(сегодня|завтра|послезавтра)"#) { g in
            switch g[1]?.lowercased() {
            case "сегодня": .day(offset: 0)
            case "завтра": .day(offset: 1)
            default: .day(offset: 2)
            }
        }
        static let weekday = Rule(.due, #"(?:в|во|на)\s+("# + weekdays.map(\.0).joined(separator: "|") + ")") { g in
            let word = g[1]?.lowercased() ?? ""
            return weekdays.first { $0.0 == word }.map { .weekday($0.1) }
        }
        static let numericDate = Rule(.due, #"(?:(?:в|на|к|до)\s+)?(\d{1,2})\.(\d{1,2})(?:\.(\d{2}|\d{4}))?"#) { g in
            guard let d = g[1].flatMap(Int.init), let m = g[2].flatMap(Int.init), (1...31).contains(d), (1...12).contains(m)
            else { return nil }
            return .date(day: d, month: m, year: g[3].flatMap(Int.init))
        }
        static let monthDate = Rule(.due, #"(?:(?:в|на|к|до)\s+)?(\d{1,2})\s+("# + months.map(\.0).joined(separator: "|") + ")") { g in
            let word = g[2]?.lowercased() ?? ""
            guard let d = g[1].flatMap(Int.init), (1...31).contains(d), let m = months.first(where: { $0.0 == word })?.1
            else { return nil }
            return .date(day: d, month: m, year: nil)
        }
        /// «в 10», «в 10:30», «в 9 вечера».
        static let time = Rule(.due, #"в\s+(\d{1,2})(?::(\d{2}))?(?:\s+(утра|дня|вечера|ночи))?"#) { g in clock(g[1], g[2], g[3]) }
        /// «15:30» without «в».
        static let clock = Rule(.due, #"(\d{1,2}):(\d{2})(?:\s+(утра|дня|вечера|ночи))?"#) { g in clock(g[1], g[2], g[3]) }

        static func clock(_ h: String?, _ m: String?, _ part: String?) -> Value? {
            guard let h = h.flatMap(Int.init), (0...23).contains(h) else { return nil }
            let m = m.flatMap(Int.init) ?? 0
            guard (0...59).contains(m) else { return nil }
            return .time(hour: h, minute: m, part: part.flatMap { DayPart(rawValue: $0.lowercased()) })
        }

        // Longest first: the alternation takes the first that fits.
        static let weekdays: [(String, Int)] = [
            ("понедельник", 2), ("вторник", 3), ("среду", 4), ("среда", 4), ("четверг", 5), ("пятницу", 6), ("пятница", 6),
            ("субботу", 7), ("суббота", 7), ("воскресенье", 1),
            ("пн", 2), ("вт", 3), ("ср", 4), ("чт", 5), ("пт", 6), ("сб", 7), ("вс", 1),
        ]
        static let months: [(String, Int)] = [
            ("января", 1), ("февраля", 2), ("марта", 3), ("апреля", 4), ("мая", 5), ("июня", 6), ("июля", 7),
            ("августа", 8), ("сентября", 9), ("октября", 10), ("ноября", 11), ("декабря", 12),
            ("янв", 1), ("фев", 2), ("мар", 3), ("апр", 4), ("июн", 6), ("июл", 7), ("авг", 8),
            ("сент", 9), ("сен", 9), ("окт", 10), ("нояб", 11), ("ноя", 11), ("дек", 12),
        ]
    }
}
