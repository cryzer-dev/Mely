import Foundation
import Observation

/// One plan window (5 hours or 7 days) as Claude Code's statusLine reports it.
public struct PlanWindow: Equatable, Codable, Sendable {
    /// 0–100, above 100 once exceeded.
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(usedPercent: Double, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    /// `{"used_percentage": 42.5, "resets_at": 1738425600}` (Unix seconds).
    init?(_ raw: Any?) {
        guard let obj = raw as? [String: Any], let used = (obj["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
        usedPercent = used
        resetsAt = Self.date(obj["resets_at"])
    }

    /// Unix seconds; milliseconds and ISO 8601 are accepted too, in case the format moves.
    static func date(_ raw: Any?) -> Date? {
        if let n = (raw as? NSNumber)?.doubleValue, n > 0 {
            return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
        }
        if let s = raw as? String {
            return ISO8601DateFormatter().date(from: s)
                ?? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: s) }()
        }
        return nil
    }

    public var isWarning: Bool { usedPercent >= PlanUsage.warningPercent }
}

/// Plan limits from the latest statusLine call of any session.
public struct PlanUsage: Equatable, Codable, Sendable {
    public static let warningPercent = 80.0

    public var fiveHour: PlanWindow?
    public var sevenDay: PlanWindow?
    public var updatedAt: Date
    /// The plan's name when the agent reports it (Codex: «plus», «pro»…).
    public var plan: String?
    /// Free limit resets left (Codex); nil when the agent has none.
    public var resetCredits: Int?

    public init(fiveHour: PlanWindow?, sevenDay: PlanWindow?, updatedAt: Date, plan: String? = nil, resetCredits: Int? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.updatedAt = updatedAt
        self.plan = plan
        self.resetCredits = resetCredits
    }

    /// Nil when the payload has no window (API key sessions: `rate_limits` is null or empty).
    public init?(rateLimits: [String: Any], now: Date = Date()) {
        let five = PlanWindow(rateLimits["five_hour"]), week = PlanWindow(rateLimits["seven_day"])
        guard five != nil || week != nil else { return nil }
        self.init(fiveHour: five, sevenDay: week, updatedAt: now)
    }

    public var isWarning: Bool { fiveHour?.isWarning == true || sevenDay?.isWarning == true }

    /// Past this, the numbers are shown as old, with their age.
    public static let staleAfter: TimeInterval = 15 * 60

    /// No statusLine call for a while: the numbers may have moved since.
    public func isStale(now: Date = Date()) -> Bool { now.timeIntervalSince(updatedAt) > Self.staleAfter }

    /// "обновлено 2 ч 5 мин назад": how old the numbers are.
    public func ageText(now: Date = Date()) -> String {
        "обновлено \(Self.countdown(to: now, from: updatedAt)) назад"
    }

    public enum Kind: Sendable {
        case fiveHour, sevenDay

        /// "за 5 часов", "за неделю": after «Лимит Claude».
        public var span: String {
            switch self {
            case .fiveHour: "за 5 часов"
            case .sevenDay: "за неделю"
            }
        }
    }

    /// What the compact island shows: a window used up, as the one that frees up later
    /// (no work before that), else the five-hour window. The week otherwise lives in the
    /// overview and the card.
    public var compactWindow: (kind: Kind, window: PlanWindow)? {
        let windows = [(Kind.fiveHour, fiveHour), (Kind.sevenDay, sevenDay)]
            .compactMap { kind, window in window.map { (kind: kind, window: $0) } }
        let spent = windows.filter { $0.window.usedPercent >= 100 && $0.window.resetsAt != nil }
        if let later = spent.max(by: { $0.window.resetsAt! < $1.window.resetsAt! }) { return later }
        return fiveHour.map { (.fiveHour, $0) }
    }

    /// The fuller window (how worried Mely looks).
    public var fullest: PlanWindow? {
        [fiveHour, sevenDay].compactMap { $0 }.max { $0.usedPercent < $1.usedPercent }
    }

    /// A window whose reset time passed starts over at 0%.
    public func current(now: Date = Date()) -> PlanUsage {
        func fresh(_ w: PlanWindow?) -> PlanWindow? {
            guard let w, let reset = w.resetsAt, reset <= now else { return w }
            return PlanWindow(usedPercent: 0, resetsAt: nil)
        }
        return PlanUsage(fiveHour: fresh(fiveHour), sevenDay: fresh(sevenDay), updatedAt: updatedAt, plan: plan,
                         resetCredits: resetCredits)
    }

    /// For the narrow compact island: "1ч 28м", "45м", "2д 4ч".
    public static func shortCountdown(to date: Date, from now: Date = Date()) -> String {
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)м" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "\(hours)ч" : "\(hours)ч \(minutes % 60)м" }
        return hours % 24 == 0 ? "\(hours / 24)д" : "\(hours / 24)д \(hours % 24)ч"
    }

    /// "2 ч 14 мин", "3 дн 4 ч", "45 мин", "меньше минуты".
    public static func countdown(to date: Date, from now: Date = Date()) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "сейчас" }
        if minutes < 60 { return "\(minutes) мин" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "\(hours) ч" : "\(hours) ч \(minutes % 60) мин" }
        return hours % 24 == 0 ? "\(hours / 24) дн" : "\(hours / 24) дн \(hours % 24) ч"
    }
}

/// One agent's latest plan usage, kept across launches so the overview has something to
/// show before the first session of the day. Each agent has its own store and its own age.
@MainActor
@Observable
public final class PlanUsageStore {
    public let agent: Agent
    public private(set) var usage: PlanUsage?
    /// Why there are no numbers, when the agent said (Codex: «войди через ChatGPT»).
    public var problem: String?
    @ObservationIgnored private let defaults: UserDefaults
    static let defaultsKey = "planUsage"

    /// Claude's under the key it always had: the numbers saved before agents stay Claude's.
    static func key(_ agent: Agent) -> String { agent == .claude ? defaultsKey : "\(defaultsKey).\(agent.rawValue)" }

    public init(agent: Agent = .claude, defaults: UserDefaults = .standard) {
        self.agent = agent
        self.defaults = defaults
        usage = defaults.data(forKey: Self.key(agent)).flatMap { try? JSONDecoder().decode(PlanUsage.self, from: $0) }
    }

    /// Takes a reading asked for (Codex's app server): kept as it is.
    public func set(_ new: PlanUsage) {
        usage = new
        problem = nil
        if let data = try? JSONEncoder().encode(new) { defaults.set(data, forKey: Self.key(agent)) }
    }

    /// Takes a statusLine report. Reports without windows (API key) keep the last values.
    public func update(rateLimits: [String: Any], now: Date = Date()) {
        guard let new = PlanUsage(rateLimits: rateLimits, now: now) else { return }
        // statusLine runs on every redraw: write only when a window actually moved.
        let moved = new.fiveHour != usage?.fiveHour || new.sevenDay != usage?.sevenDay
        usage = new
        guard moved else { return }
        if let data = try? JSONEncoder().encode(new) { defaults.set(data, forKey: Self.key(agent)) }
    }
}
