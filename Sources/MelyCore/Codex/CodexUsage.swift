import Foundation

/// Codex's plan limits from its app server (`account/rateLimits/read`), as `PlanUsage`.
public enum CodexUsage {
    /// Not signed in to Codex with ChatGPT: no limits to read.
    public static let signedOut = "Нет данных: войди в Codex через ChatGPT"

    /// The response as `PlanUsage`; nil when it has no window. A window up to a day long is
    /// the short one, longer is the week; without lengths, primary is short, secondary the week.
    public static func parse(_ response: [String: Any], now: Date = Date()) -> PlanUsage? {
        let byId = response["rateLimitsByLimitId"] as? [String: Any]
        let snapshot = (byId?["codex"] as? [String: Any]) ?? (response["rateLimits"] as? [String: Any]) ?? [:]
        var fiveHour: PlanWindow?, sevenDay: PlanWindow?
        for (slot, isPrimary) in [("primary", true), ("secondary", false)] {
            guard let raw = snapshot[slot] as? [String: Any], let used = (raw["usedPercent"] as? NSNumber)?.doubleValue else { continue }
            let window = PlanWindow(usedPercent: used, resetsAt: PlanWindow.date(raw["resetsAt"]))
            let minutes = (raw["windowDurationMins"] as? NSNumber)?.intValue
            let short = minutes.map { $0 <= 24 * 60 } ?? isPrimary
            if short, fiveHour == nil { fiveHour = window } else if sevenDay == nil { sevenDay = window }
        }
        guard fiveHour != nil || sevenDay != nil else { return nil }
        let credits = ((response["rateLimitResetCredits"] as? [String: Any])?["availableCount"] as? NSNumber)?.intValue
        let plan = (snapshot["planType"] as? String) ?? ((response["rateLimits"] as? [String: Any])?["planType"] as? String)
        return PlanUsage(fiveHour: fiveHour, sevenDay: sevenDay, updatedAt: now, plan: plan.flatMap { $0 == "unknown" ? nil : $0 },
                         resetCredits: credits.flatMap { $0 > 0 ? $0 : nil })
    }

    /// Asks Codex. Signed out comes back as `CodexAppServer.Failure.rpc` with Codex's words;
    /// `problem(for:)` turns any failure into what the card says.
    public static func read(codex: URL, now: Date = Date(), timeout: TimeInterval = CodexAppServer.timeout) async throws -> PlanUsage? {
        parse(try await CodexAppServer.request("account/rateLimits/read", codex: codex, timeout: timeout), now: now)
    }

    /// What the limits card says instead of numbers.
    public static func problem(for error: Error) -> String {
        if case CodexAppServer.Failure.rpc(let message) = error, message.localizedCaseInsensitiveContains("authentication") {
            return signedOut
        }
        return "Нет данных: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
    }
}

/// When to ask Codex for its limits: only while they are on screen, and not often.
public enum CodexUsagePoll {
    public enum Visibility: Sendable {
        /// In the open island (the header ring, the card or the strip).
        case open
        /// Only in the closed notch's wing (Codex pinned there).
        case wing
        case hidden
    }

    public static let openInterval: TimeInterval = 60
    public static let wingInterval: TimeInterval = 5 * 60

    /// Whether to ask now, given the last ask (or attempt).
    public static func isDue(last: Date?, now: Date, visibility: Visibility) -> Bool {
        let interval: TimeInterval
        switch visibility {
        case .open: interval = openInterval
        case .wing: interval = wingInterval
        case .hidden: return false
        }
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }
}
