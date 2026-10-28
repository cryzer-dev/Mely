import Foundation

/// How long a task should take: a short scale, more than an hour is "1 ч+".
public enum TaskEstimate: Int, CaseIterable, Sendable {
    case m15 = 15, m30 = 30, m45 = 45, h1 = 60, overHour = 61

    /// Rounded up to the scale: 20 min is "~30 мин", anything over an hour "1 ч+".
    public init?(minutes: Int) {
        guard minutes > 0 else { return nil }
        switch minutes {
        case ...15: self = .m15
        case ...30: self = .m30
        case ...45: self = .m45
        case ...60: self = .h1
        default: self = .overHour
        }
    }

    /// What it adds to a day's sum: "1 ч+" counts as an hour.
    public var minutes: Int { self == .overHour ? 60 : rawValue }

    /// The chip: "~30 мин", "~1 ч", "1 ч+".
    public var label: String {
        switch self {
        case .m15, .m30, .m45: "~\(rawValue) мин"
        case .h1: "~1 ч"
        case .overHour: "1 ч+"
        }
    }

    /// As written in the notes: "~30 мин", "~1 ч", "~1 ч+".
    var mark: String { self == .overHour ? "~1 ч+" : label }

    /// A sum of minutes: "45 мин", "1 ч", "2 ч 30 мин".
    public static func format(totalMinutes: Int) -> String {
        let h = totalMinutes / 60, m = totalMinutes % 60
        if h == 0 { return "\(m) мин" }
        return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин"
    }
}

/// Tags and the estimate, which Reminders has no API for. Mely keeps them as the last
/// line of the task's notes, `#работа #релиз · ~45 мин`, so they sync to the iPhone and
/// can be fixed by hand there.
public struct TaskMarks: Equatable, Sendable {
    public var tags: [String]
    public var estimate: TaskEstimate?

    public init(tags: [String] = [], estimate: TaskEstimate? = nil) {
        self.tags = Self.unique(tags)
        self.estimate = estimate
    }

    public var isEmpty: Bool { tags.isEmpty && estimate == nil }

    /// The line written to the notes; nil when there is nothing to write.
    public var line: String? {
        var parts: [String] = []
        if !tags.isEmpty { parts.append(tags.map { "#" + $0 }.joined(separator: " ")) }
        if let estimate { parts.append(estimate.mark) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Splits the notes into the user's text and the marks. Only a last line made of tags
    /// and an estimate alone counts; anything else is left as text.
    public static func parse(notes: String?) -> (body: String, marks: TaskMarks) {
        let notes = notes ?? ""
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastBreak = trimmed.lastIndex(where: \.isNewline)
        let last = lastBreak.map { String(trimmed[trimmed.index(after: $0)...]) } ?? trimmed
        guard let marks = marks(in: last.trimmingCharacters(in: .whitespaces)) else { return (notes, TaskMarks()) }
        let body = lastBreak.map { String(trimmed[..<$0]) } ?? ""
        return (body.trimmingCharacters(in: .newlines), marks)
    }

    /// The notes with these marks as the last line; the rest of the text untouched.
    /// Nil: the notes end up empty.
    public static func write(_ marks: TaskMarks, into notes: String?) -> String? {
        let body = parse(notes: notes).body
        let parts = [body.isEmpty ? nil : body, marks.line].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    // MARK: - Parsing

    private static let tag = #"#([\p{L}\p{N}_-]+)"#
    /// `~45м`, `~45 мин`, `~1ч`, `~1,5 ч`, `~1 ч 30 мин`, `~2 часа`, `~1 ч+`.
    static let estimatePattern = #"~(\d+(?:[.,]\d+)?)\s*(мин|м|час(?:а|ов)?|ч)(?:\s*(\d+)\s*(?:мин|м))?(\+)?"#
    private static let line = try! NSRegularExpression(
        pattern: #"^((?:\#(tag)\s*)*)(?:·\s*)?(?:\#(estimatePattern))?$"#)
    private static let tagRegex = try! NSRegularExpression(pattern: tag)

    private static func marks(in text: String) -> TaskMarks? {
        let range = NSRange(text.startIndex..., in: text)
        guard !text.isEmpty, let m = line.firstMatch(in: text, range: range) else { return nil }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: text).map { String(text[$0]) } }
        let tagText = group(1) ?? ""
        let tags = tagRegex.matches(in: tagText, range: NSRange(tagText.startIndex..., in: tagText)).compactMap {
            Range($0.range(at: 1), in: tagText).map { String(tagText[$0]) }
        }
        // Capture groups: 1 tags, 2 inner tag, 3 number, 4 unit, 5 extra minutes, 6 "+".
        let estimate = estimate(number: group(3), unit: group(4), extra: group(5), plus: group(6) != nil)
        guard !tags.isEmpty || estimate != nil else { return nil }
        return TaskMarks(tags: tags, estimate: estimate)
    }

    /// The estimate from the parts of `estimatePattern`, rounded up to the scale.
    static func estimate(number: String?, unit: String?, extra: String?, plus: Bool) -> TaskEstimate? {
        guard let number, let value = Double(number.replacingOccurrences(of: ",", with: ".")), let unit else { return nil }
        let inHours = unit.hasPrefix("ч")
        var minutes = inHours ? value * 60 : value
        if let extra, let m = Double(extra) { minutes += m }
        if plus && minutes >= 60 { return .overHour }
        return TaskEstimate(minutes: Int(minutes.rounded(.up)))
    }

    private static func unique(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.filter { seen.insert($0.lowercased()).inserted }
    }
}
