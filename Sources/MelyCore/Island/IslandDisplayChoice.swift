// Portions © 2026 Louis Raillé, MIT License — see THIRD_PARTY_NOTICES.md.

/// Which screen hosts the island. Persisted in UserDefaults as `storageValue`.
public enum IslandDisplayChoice: Equatable, Hashable, Sendable {
    /// Default: the built-in screen with a notch, else the main screen.
    case notch
    /// The screen that carries the menu bar (first in `NSScreen.screens`).
    case menuBar
    /// The island moves to the screen under the cursor while it is not open.
    case followMouse
    /// A specific screen, identified by its display UUID (stable across reboots).
    case display(uuid: String)

    public static let defaultsKey = "islandDisplay"
    private static let displayPrefix = "display:"

    public init(storageValue: String) {
        switch storageValue {
        case "menuBar":     self = .menuBar
        case "followMouse": self = .followMouse
        default:
            if storageValue.hasPrefix(Self.displayPrefix) {
                let uuid = String(storageValue.dropFirst(Self.displayPrefix.count))
                self = uuid.isEmpty ? .notch : .display(uuid: uuid)
            } else {
                self = .notch
            }
        }
    }

    public var storageValue: String {
        switch self {
        case .notch:             return "notch"
        case .menuBar:           return "menuBar"
        case .followMouse:       return "followMouse"
        case .display(let uuid): return Self.displayPrefix + uuid
        }
    }
}

/// What the resolver needs to know about a connected screen, in `NSScreen.screens` order.
public struct IslandDisplayCandidate: Sendable {
    public let uuid: String?
    public let hasNotch: Bool
    public let containsMouse: Bool

    public init(uuid: String?, hasNotch: Bool, containsMouse: Bool) {
        self.uuid = uuid
        self.hasNotch = hasNotch
        self.containsMouse = containsMouse
    }
}

public enum IslandDisplayResolver {
    /// Index of the screen that should host the island, or nil to use the default
    /// (notch screen, else main screen). A disconnected chosen screen falls back too.
    public static func index(for choice: IslandDisplayChoice,
                             in candidates: [IslandDisplayCandidate]) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let notchIndex = candidates.firstIndex { $0.hasNotch }
        switch choice {
        case .notch:
            return notchIndex
        case .menuBar:
            return 0
        case .followMouse:
            return candidates.firstIndex { $0.containsMouse } ?? notchIndex
        case .display(let uuid):
            return candidates.firstIndex { $0.uuid == uuid } ?? notchIndex
        }
    }
}
