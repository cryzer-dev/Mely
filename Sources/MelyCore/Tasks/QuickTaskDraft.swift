import Foundation

/// The «+ Задача» line: the typed text plus what the chips set. The last action wins:
/// a chip cuts the matching piece out of the text, and typing that field again drops
/// the chip's choice. Empty fields take the tab's filter (its list and tag; a due of
/// today under «Сегодня»).
public struct QuickTaskDraft: Equatable, Sendable {
    public private(set) var text = ""
    /// Chip choices; `.some(nil)` is "без срока" / "без оценки" picked on purpose.
    private var due: TaskDue??
    private var priority: TaskPriority?
    private var estimate: TaskEstimate??
    private var listId: String?
    private var addedTags: [String] = []
    /// The filter's tag, taken off by hand.
    private var removedTags: Set<String> = []

    public init(text: String = "") {
        self.text = text
    }

    public mutating func setText(_ new: String) {
        let typed = Set(QuickTaskParser.tokens(in: new).map(\.field))
        if typed.contains(.due) { due = nil }
        if typed.contains(.priority) { priority = nil }
        if typed.contains(.estimate) { estimate = nil }
        text = new
    }

    /// «Сегодня», «Завтра», 📅, «Без срока».
    public mutating func setDue(_ value: TaskDue?) {
        cut(.due)
        due = .some(value)
    }

    public mutating func setPriority(_ value: TaskPriority) {
        cut(.priority)
        priority = value
    }

    /// ⏱; nil: «без оценки».
    public mutating func setEstimate(_ value: TaskEstimate?) {
        cut(.estimate)
        estimate = .some(value)
    }

    public mutating func setList(_ id: String?) {
        listId = id
    }

    public mutating func addTag(_ tag: String) {
        let tag = tag.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
        guard !tag.isEmpty else { return }
        removedTags.remove(tag.lowercased())
        if !addedTags.contains(where: { $0.lowercased() == tag.lowercased() }) { addedTags.append(tag) }
    }

    public mutating func removeTag(_ tag: String) {
        let key = tag.lowercased()
        let typed = QuickTaskParser.tokens(in: text).filter {
            if case let .tag(t) = $0.value { t.lowercased() == key } else { false }
        }
        text = QuickTaskParser.removing(typed.map(\.range), from: text)
        addedTags.removeAll { $0.lowercased() == key }
        removedTags.insert(key)
    }

    /// What the chips show, even before there is a title.
    public func preview(filter: TaskFilter, now: Date, calendar: Calendar = .current) -> QuickTask {
        var task = QuickTaskParser.parse(text, now: now, calendar: calendar)
        if let due { task.due = due }
        if let priority { task.priority = priority }
        if let estimate { task.estimate = estimate }
        if task.due == nil, due == nil, filter.period == .today { task.due = .day(of: now, calendar: calendar) }
        task.listId = listId ?? filter.listId
        var tags = task.tags + addedTags
        if let tag = filter.tag { tags.append(tag) }
        task.tags = TaskMarks(tags: tags.filter { !removedTags.contains($0.lowercased()) }).tags
        return task
    }

    /// The task to save on Enter; nil while the title is empty («#работа !!»).
    public func resolved(filter: TaskFilter, now: Date, calendar: Calendar = .current) -> QuickTask? {
        let task = preview(filter: filter, now: now, calendar: calendar)
        return task.title.isEmpty ? nil : task
    }

    /// After saving: an empty line, chips back to the filter's defaults.
    public mutating func reset() {
        self = QuickTaskDraft()
    }

    private mutating func cut(_ field: QuickTaskParser.Field) {
        let ranges = QuickTaskParser.tokens(in: text).filter { $0.field == field }.map(\.range)
        if !ranges.isEmpty { text = QuickTaskParser.removing(ranges, from: text) }
    }
}
