import Foundation

/// What Mely shows with its face and body (task 6.7).
public enum CharacterPose: String, CaseIterable, Sendable {
    /// Nothing going on: breathes, blinks, looks at the pointer.
    case idle
    /// Claude thinks or works: focused eyes, dots turning.
    case working
    /// A permission waits: worried, a sweat drop.
    case worried
    /// Claude asks a question: curious, head tilted, a "?".
    case curious
    /// Claude finished: happy eyes, a little jump, sparkles.
    case happy
    /// Something failed: startled.
    case scared
    /// The plan limit is (nearly) used up: sad, a tear.
    case sad
    /// Music plays: sways, notes float.
    case dancing
    /// Night, or long without anything: eyes closed, "zZ".
    case sleeping
    /// A focus session runs: squinting, calm, follows the pointer less, nods now and then.
    case focused
    /// A focus break: a mug of tea in the paws, a stretch every so often.
    case resting

    public var title: String {
        switch self {
        case .idle: "Ждёт"
        case .working: "Работает"
        case .worried: "Ждёт разрешения"
        case .curious: "Вопрос"
        case .happy: "Готово"
        case .scared: "Ошибка"
        case .sad: "Лимит"
        case .dancing: "Музыка"
        case .sleeping: "Спит"
        case .focused: "Фокус"
        case .resting: "Перерыв"
        }
    }
}

/// Everything the pose depends on, gathered by the app.
public struct CharacterInputs: Sendable {
    public var sessions: [SessionState]
    /// When a session last reported anything.
    public var lastActivity: Date?
    public var pendingApprovals: Int
    public var pendingQuestions: Int
    public var musicPlaying: Bool
    /// The fuller plan window, 0–100.
    public var planPercent: Double?
    /// A focus session or its break.
    public var focus: FocusMood?

    public init(sessions: [SessionState] = [], lastActivity: Date? = nil, pendingApprovals: Int = 0,
                pendingQuestions: Int = 0, musicPlaying: Bool = false, planPercent: Double? = nil, focus: FocusMood? = nil) {
        self.focus = focus
        self.sessions = sessions
        self.lastActivity = lastActivity
        self.pendingApprovals = pendingApprovals
        self.pendingQuestions = pendingQuestions
        self.musicPlaying = musicPlaying
        self.planPercent = planPercent
    }
}

/// What of the focus shows in Mely.
public enum FocusMood: Sendable {
    case working, resting
}

public extension FocusTimer {
    /// Working: focused; on a break: resting. Paused, finished or idle: Mely as usual.
    var mood: FocusMood? {
        switch phase {
        case .working: .working
        case .onBreak: .resting
        default: nil
        }
    }
}

public enum CharacterMood {
    /// After this long without anything, Mely dozes off.
    public static let sleepAfter: TimeInterval = 20 * 60

    /// The pose, most urgent first: what needs the user, then what went wrong, then the
    /// user's own focus, then what is going on, then rest.
    public static func pose(_ i: CharacterInputs, now: Date = Date(), calendar: Calendar = .current) -> CharacterPose {
        if i.pendingApprovals > 0 || i.sessions.contains(.waitingApproval) { return .worried }
        if i.pendingQuestions > 0 || i.sessions.contains(.waitingAnswer) { return .curious }
        // An error stays in its session until the next event: startled only for a while.
        let recent = i.lastActivity.map { now.timeIntervalSince($0) < 5 * 60 } ?? false
        if recent, i.sessions.contains(where: { if case .error = $0 { true } else { false } }) { return .scared }
        if i.sessions.contains(.rateLimited) || (i.planPercent ?? 0) >= 90 { return .sad }
        switch i.focus {
        case .working: return .focused
        case .resting: return .resting
        case nil: break
        }
        if i.sessions.contains(where: { if case .finished = $0 { true } else { false } }) { return .happy }
        if i.sessions.contains(.thinking) || i.sessions.contains(.working) { return .working }
        if i.musicPlaying { return .dancing }
        // Asleep after 20 quiet minutes; at night also right after launch, before any activity.
        let hour = calendar.component(.hour, from: now)
        let night = hour >= 23 || hour < 7
        if let last = i.lastActivity {
            return now.timeIntervalSince(last) > sleepAfter ? .sleeping : .idle
        }
        return night ? .sleeping : .idle
    }

    /// One session's own little Mely (the small ones in the session list).
    public static func pose(for state: SessionState) -> CharacterPose {
        switch state {
        case .idle: .idle
        case .thinking, .working: .working
        case .waitingApproval: .worried
        case .waitingAnswer: .curious
        case .finished: .happy
        case .error: .scared
        case .rateLimited: .sad
        }
    }
}
