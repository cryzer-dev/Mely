import Foundation
import Observation

/// Something an integration asks the island to show.
public struct IslandItem: Identifiable, Equatable, Sendable {
    /// Ordered by how much it needs the user: a pending approval beats everything.
    public enum Kind: Int, Comparable, Sendable {
        case approval = 0, question, meetingSoon, message, calendarChange, nowPlaying, agentActivity

        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }

        /// Kinds that keep the island open until answered.
        public var holdsIslandOpen: Bool { self == .approval || self == .question }
    }

    public let id: String
    public let kind: Kind
    /// Id of the integration that posted it.
    public let source: String
    public let createdAt: Date
    /// Message previews go away by themselves.
    public var expiresAt: Date?
    public var title: String
    public var subtitle: String?

    public init(id: String, kind: Kind, source: String, title: String, subtitle: String? = nil,
                createdAt: Date = Date(), expiresAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.source = source
        self.title = title
        self.subtitle = subtitle
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

/// Collects what the integrations want to show and picks what the island shows first.
@MainActor
@Observable
public final class IslandModel {
    public private(set) var items: [IslandItem] = []

    public init() {}

    /// Adds or replaces (same id) an item.
    public func post(_ item: IslandItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i] = item
        } else {
            items.append(item)
        }
    }

    public func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    /// Drops everything an integration posted (it was switched off).
    public func removeAll(from source: String) {
        items.removeAll { $0.source == source }
    }

    /// Drops expired items.
    public func prune(now: Date = Date()) {
        items.removeAll { ($0.expiresAt ?? .distantFuture) <= now }
    }

    /// Items in display order: most urgent kind first, then oldest first within a kind
    /// (approvals are answered in the order they came).
    public func ordered(now: Date = Date()) -> [IslandItem] {
        items
            .filter { ($0.expiresAt ?? .distantFuture) > now }
            .sorted { $0.kind != $1.kind ? $0.kind < $1.kind : $0.createdAt < $1.createdAt }
    }

    /// What the compact island shows.
    public func top(now: Date = Date()) -> IslandItem? { ordered(now: now).first }

    /// True while an approval or a question waits for the user.
    public var holdsIslandOpen: Bool { items.contains { $0.kind.holdsIslandOpen } }
}
