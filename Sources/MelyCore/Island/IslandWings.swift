import Foundation

/// The compact island's wings (the parts left and right of the notch) cover menu bar
/// items, so when they show is the user's choice (`Mode`): while anything is live, a few
/// seconds on an event, or only under the pointer. A waiting request always shows them.
/// The rest of the time the island is just the notch.
public struct IslandWings: Equatable, Sendable {
    /// How long an event keeps the wings out.
    public static let showFor: TimeInterval = 5

    /// The user's choice in Settings → «Боковые части челки».
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        /// While anything is live: Claude works or waits, music plays, a limit is near, a focus runs.
        case whileActive
        /// A few seconds on an event, then just the notch.
        case flash
        /// Only under the pointer (and while a request waits).
        case hoverOnly

        public static let `default` = Mode.whileActive
        public static let defaultsKey = "islandWings"
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .whileActive: "Пока есть активность"
            case .flash: "На 5 секунд при событии"
            case .hoverOnly: "Только при наведении"
            }
        }

        public static func stored(_ defaults: UserDefaults = .standard) -> Mode {
            Mode(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .default
        }
    }

    /// Until when the latest event keeps them out.
    public private(set) var until: Date?

    public init() {}

    /// An event worth seeing: wings out for `showFor`.
    public mutating func flash(now: Date = Date()) {
        until = max(until ?? now, now.addingTimeInterval(Self.showFor))
    }

    /// - Parameters:
    ///   - hovering: the pointer is on the island.
    ///   - pinned: something waits for the user (an approval or a question).
    ///   - live: something is going on (Claude works, music plays, a limit is near).
    public func showsWings(hovering: Bool, pinned: Bool, live: Bool = false, mode: Mode = .flash,
                           now: Date = Date()) -> Bool {
        if hovering || pinned { return true }
        switch mode {
        case .whileActive: return live || (until.map { now < $0 } ?? false)
        case .flash: return until.map { now < $0 } ?? false
        case .hoverOnly: return false
        }
    }

    /// Claude Code keeps something going: a turn runs or waits for the user, or a plan
    /// limit is near; or a focus session or break runs. (Music is added by the app.)
    public static func live(states: [SessionState], usage: PlanUsage?, focus: FocusTimer? = nil, now: Date = Date()) -> Bool {
        focus?.isLive == true
            || states.contains { [.thinking, .working, .waitingApproval, .waitingAnswer].contains($0) }
            || usage?.current(now: now).isWarning == true
    }

    /// A session entering a new turn is worth a flash; every tool step of it is not.
    public static func startsTurn(from old: SessionState?, to new: SessionState) -> Bool {
        let busy: (SessionState?) -> Bool = { $0 == .thinking || $0 == .working }
        return busy(new) && !busy(old)
    }
}
