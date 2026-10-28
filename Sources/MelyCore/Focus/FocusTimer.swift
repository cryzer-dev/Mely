import Foundation

/// The task a focus session is on.
public struct FocusTaskRef: Codable, Equatable, Sendable {
    /// `TaskItem.id`.
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// A meeting from the calendar that may cut a focus session short.
public struct FocusMeeting: Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date

    public init(id: String, title: String, start: Date) {
        self.id = id
        self.title = title
        self.start = start
    }
}

/// Break lengths, read when a break starts: a change applies from the next one.
public struct FocusRhythm: Equatable, Sendable {
    public var shortBreak: TimeInterval
    public var longBreak: TimeInterval
    /// Every N-th session in a row ends with the long break.
    public var longEvery: Int

    public init(shortBreak: TimeInterval = 5 * 60, longBreak: TimeInterval = 15 * 60, longEvery: Int = 4) {
        self.shortBreak = shortBreak
        self.longBreak = longBreak
        self.longEvery = longEvery
    }
}

/// What a transition or a tick asks `FocusIntegration` to show, play or log.
public enum FocusEvent: Equatable, Sendable {
    case started
    /// Time is up; `worked` is the session's counted time.
    case finished(worked: TimeInterval)
    case breakStarted(TimeInterval)
    case breakOver
    /// Paused for no input; the preview waits for the return.
    case autoPaused
    /// Back after an away, lock or sleep pause: «тебя не было N мин».
    case returned(away: TimeInterval)
    case meetingSoon(FocusMeeting)
    /// Write (or rewrite, by id) this session in the log.
    case record(FocusRecord)
}

/// Focus sessions and breaks as a value: every transition takes `now`, there are no timers
/// inside. Time is counted from dates, not from ticks, so a missed tick (sleep, load) loses nothing.
public struct FocusTimer: Codable, Equatable, Sendable {
    public enum Phase: Codable, Equatable, Sendable {
        case idle, working, paused(PauseReason), finished, onBreak, breakOver
    }

    public enum PauseReason: String, Codable, Sendable {
        /// «Пауза» or ⌃⌥P; only the user lifts it.
        case manual
        /// No input for a while.
        case away
        /// Screen locked or the Mac asleep.
        case locked
    }

    /// Sessions this far apart are no longer "in a row".
    public static let streakGap: TimeInterval = 30 * 60
    /// How early a meeting is announced.
    public static let meetingLead: TimeInterval = 5 * 60

    public private(set) var phase: Phase = .idle
    public private(set) var task: FocusTaskRef?
    /// The session's chosen length, reused by «Продолжить» after a break.
    public private(set) var duration: TimeInterval = 0
    public private(set) var sessionId: String?
    public private(set) var start: Date?
    /// While paused, stale: the remaining time is `plannedEnd − pausedAt`.
    public private(set) var plannedEnd: Date?
    /// Counted up to `resumedAt`.
    public private(set) var worked: TimeInterval = 0
    public private(set) var resumedAt: Date?
    public private(set) var pausedAt: Date?
    public private(set) var breakLength: TimeInterval = 0
    public private(set) var breakEnd: Date?
    /// Finished sessions in a row, for the long break.
    public private(set) var streak = 0
    public private(set) var lastSessionEnd: Date?
    /// Saved with every tick: the restore after a relaunch counts no further than this.
    public private(set) var lastInputAt: Date?
    /// The session is already in `streak` (finished, then «Ещё 10 мин»).
    private var counted = false
    private var returnAnnounced = false
    private var warnedMeetings: Set<String> = []

    public init() {}

    /// Working or paused: a new start has to replace it.
    public var isRunning: Bool {
        switch phase {
        case .working, .paused: true
        default: false
        }
    }

    public var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    /// Counted time so far, without pauses and past the planned end.
    public func worked(now: Date) -> TimeInterval {
        guard phase == .working, let resumedAt, let plannedEnd else { return worked }
        return worked + max(0, min(now, plannedEnd).timeIntervalSince(resumedAt))
    }

    /// Time left of the session or the break.
    public func remaining(now: Date) -> TimeInterval {
        switch phase {
        case .working: max(0, plannedEnd.map { $0.timeIntervalSince(now) } ?? 0)
        case .paused: max(0, pausedRemaining)
        case .onBreak: max(0, breakEnd.map { $0.timeIntervalSince(now) } ?? 0)
        default: 0
        }
    }

    /// 0…1 of the session or the break, for the ring.
    public func progress(now: Date) -> Double {
        let total: TimeInterval
        switch phase {
        case .working, .paused: total = worked(now: now) + remaining(now: now)
        case .onBreak: total = breakLength
        case .finished, .breakOver: return 1
        case .idle: return 0
        }
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(now: now) / total))
    }

    private var pausedRemaining: TimeInterval {
        guard let plannedEnd, let pausedAt else { return 0 }
        return plannedEnd.timeIntervalSince(pausedAt)
    }

    /// When the session ends if nothing changes.
    private func end(now: Date) -> Date? {
        switch phase {
        case .working: plannedEnd
        case .paused: now.addingTimeInterval(pausedRemaining)
        default: nil
        }
    }

    private var record: FocusRecord? {
        guard let sessionId, let start else { return nil }
        return FocusRecord(id: sessionId, taskId: task?.id, taskTitle: task?.title, start: start, worked: worked)
    }

    // MARK: Transitions

    /// Starts a session; does nothing while one runs (see `replace`).
    @discardableResult
    public mutating func start(now: Date, duration: TimeInterval, task: FocusTaskRef? = nil) -> [FocusEvent] {
        guard !isRunning, duration > 0 else { return [] }
        if let lastSessionEnd, now.timeIntervalSince(lastSessionEnd) > Self.streakGap { streak = 0 }
        phase = .working
        self.task = task
        self.duration = duration
        sessionId = UUID().uuidString
        start = now
        plannedEnd = now.addingTimeInterval(duration)
        worked = 0
        resumedAt = now
        pausedAt = nil
        breakEnd = nil
        lastInputAt = now
        counted = false
        returnAnnounced = false
        warnedMeetings = []
        return [.started]
    }

    /// Ends the running session with its counted time and starts a new one.
    @discardableResult
    public mutating func replace(now: Date, duration: TimeInterval, task: FocusTaskRef? = nil) -> [FocusEvent] {
        stop(now: now) + start(now: now, duration: duration, task: task)
    }

    @discardableResult
    public mutating func pause(now: Date) -> [FocusEvent] {
        guard phase == .working else { return [] }
        settle(at: now)
        phase = .paused(.manual)
        return []
    }

    /// Lifts any pause; the remaining time is what it was when paused.
    @discardableResult
    public mutating func resume(now: Date) -> [FocusEvent] {
        guard isRunning, phase != .working else { return [] }
        plannedEnd = now.addingTimeInterval(pausedRemaining)
        resumedAt = now
        pausedAt = nil
        lastInputAt = now
        returnAnnounced = false
        phase = .working
        return []
    }

    /// «+5 мин» on a running session, «Ещё 10 мин» on a finished one.
    @discardableResult
    public mutating func extend(by time: TimeInterval, now: Date) -> [FocusEvent] {
        switch phase {
        case .working, .paused:
            plannedEnd = plannedEnd?.addingTimeInterval(time)
        case .finished:
            phase = .working
            plannedEnd = now.addingTimeInterval(time)
            resumedAt = now
            pausedAt = nil
            lastInputAt = now
        default:
            break
        }
        return []
    }

    /// «Стоп», «Закончить сейчас», «Хватит»: back to idle without a break, the counted time kept.
    @discardableResult
    public mutating func stop(now: Date) -> [FocusEvent] {
        var events: [FocusEvent] = []
        if isRunning {
            if phase == .working { settle(at: now) }
            if let record { events.append(.record(record)) }
            lastSessionEnd = now
        }
        reset()
        return events
    }

    /// After a finished session: the long one after every `longEvery`-th in a row.
    @discardableResult
    public mutating func takeBreak(now: Date, rhythm: FocusRhythm = FocusRhythm()) -> [FocusEvent] {
        guard phase == .finished else { return [] }
        let long = rhythm.longEvery > 0 && streak > 0 && streak % rhythm.longEvery == 0
        breakLength = long ? rhythm.longBreak : rhythm.shortBreak
        breakEnd = now.addingTimeInterval(breakLength)
        phase = .onBreak
        return [.breakStarted(breakLength)]
    }

    /// «Пропустить» on a break, or no break after a finished session.
    @discardableResult
    public mutating func skipBreak() -> [FocusEvent] {
        guard phase == .onBreak || phase == .finished else { return [] }
        reset()
        return []
    }

    /// «Продолжить» after a break: the same length and task again.
    @discardableResult
    public mutating func `continue`(now: Date) -> [FocusEvent] {
        guard phase == .breakOver || phase == .onBreak else { return [] }
        let duration = duration, task = task
        reset()
        return start(now: now, duration: duration, task: task)
    }

    /// Screen locked or the Mac about to sleep: paused at once. A break goes on.
    @discardableResult
    public mutating func lock(now: Date) -> [FocusEvent] {
        guard phase == .working else { return [] }
        settle(at: now)
        phase = .paused(.locked)
        returnAnnounced = false
        return []
    }

    /// Unlocked or awake: the pause stays, the user is asked to go on.
    @discardableResult
    public mutating func unlock(now: Date) -> [FocusEvent] {
        guard phase == .paused(.locked), !returnAnnounced, let pausedAt else { return [] }
        returnAnnounced = true
        return [.returned(away: now.timeIntervalSince(pausedAt))]
    }

    /// Called every second while something runs. `idleSeconds` is the time since the last
    /// mouse or keyboard input, nil when away tracking is off.
    @discardableResult
    public mutating func tick(now: Date, idleSeconds: TimeInterval?, nextMeeting: FocusMeeting? = nil,
                              awayAfter: TimeInterval = 5 * 60) -> [FocusEvent] {
        var events: [FocusEvent] = []
        switch phase {
        case .working:
            guard let plannedEnd, let resumedAt else { return [] }
            if let idleSeconds {
                let lastInput = now.addingTimeInterval(-idleSeconds)
                if idleSeconds >= awayAfter, lastInput < plannedEnd {
                    settle(at: max(lastInput, resumedAt))
                    phase = .paused(.away)
                    returnAnnounced = false
                    return [.autoPaused]
                }
                lastInputAt = max(lastInput, resumedAt)
            }
            if now >= plannedEnd {
                finish(at: plannedEnd)
                events.append(.finished(worked: worked))
                if let record { events.append(.record(record)) }
                return events
            }
        case .paused(.away):
            if !returnAnnounced, let idleSeconds, idleSeconds < awayAfter, let pausedAt {
                returnAnnounced = true
                events.append(.returned(away: now.timeIntervalSince(pausedAt)))
            }
        case .paused:
            break
        case .onBreak:
            if let breakEnd, now >= breakEnd {
                phase = .breakOver
                return [.breakOver]
            }
        default:
            return []
        }
        if let nextMeeting, let end = end(now: now), !warnedMeetings.contains(nextMeeting.id),
           nextMeeting.start > now, nextMeeting.start < end,
           nextMeeting.start.timeIntervalSince(now) <= Self.meetingLead {
            warnedMeetings.insert(nextMeeting.id)
            events.append(.meetingSoon(nextMeeting))
        }
        return events
    }

    /// Mely was not running: a session whose time ran out meanwhile finishes silently,
    /// counted no further than the last input saved; a break that ran out is over.
    @discardableResult
    public mutating func restore(now: Date) -> [FocusEvent] {
        switch phase {
        case .working:
            guard let plannedEnd, let resumedAt, now >= plannedEnd else { return [] }
            let cut = max(resumedAt, min(plannedEnd, lastInputAt ?? plannedEnd))
            finish(at: cut)
            lastSessionEnd = plannedEnd
            return record.map { [.record($0)] } ?? []
        case .onBreak:
            if let breakEnd, now >= breakEnd { phase = .breakOver }
            return []
        default:
            return []
        }
    }

    // MARK: Helpers

    /// Counts the time since the last resume up to `time` (never past the planned end).
    private mutating func settle(at time: Date) {
        if let resumedAt, let plannedEnd {
            worked += max(0, min(time, plannedEnd).timeIntervalSince(resumedAt))
        }
        resumedAt = nil
        pausedAt = time
    }

    private mutating func finish(at time: Date) {
        settle(at: time)
        pausedAt = nil
        phase = .finished
        if !counted {
            streak += 1
            counted = true
        }
        lastSessionEnd = time
    }

    /// Back to idle; the streak and the last session's end stay for the next start.
    private mutating func reset() {
        let streak = streak, lastSessionEnd = lastSessionEnd
        self = FocusTimer()
        self.streak = streak
        self.lastSessionEnd = lastSessionEnd
    }

    // MARK: Saving

    private static let key = "focusTimer"

    /// Saved after every transition, so an update mid-session does not lose it.
    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    public static func saved(in defaults: UserDefaults = .standard) -> FocusTimer? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(FocusTimer.self, from: $0) }
    }
}
