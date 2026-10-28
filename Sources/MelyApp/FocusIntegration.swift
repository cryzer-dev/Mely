import AppKit
import CoreGraphics
import Observation
import OSLog
import MelyCore

private let logger = Logger(subsystem: "dev.mely.app", category: "focus")

/// Focus sessions and breaks: the timer ticks while something runs, pauses when nobody is
/// at the Mac, the screen locks or the Mac sleeps, survives a relaunch and logs what was
/// worked. ⌃⌥P starts, pauses and resumes. The rules live in `FocusTimer`.
@MainActor
@Observable
final class FocusIntegration: Integration {
    let id = "focus"
    let displayName = "Фокус"
    let summary = "Таймер в челке, тишина для сообщений и сколько реально ушло на задачу"
    private(set) var status: IntegrationStatus = .off
    /// The current session or break, for the notch; idle while off.
    let model = FocusModel()
    private var timer: FocusTimer {
        get { model.timer }
        set { model.timer = newValue }
    }
    /// Nil while off: switched off, the integration holds nothing.
    private(set) var log: FocusLog?

    @ObservationIgnored let settings = FocusSettings()
    /// Every event after it is handled here (sounds, log): previews, the hold on messages.
    @ObservationIgnored var onEvent: ((FocusEvent) -> Void)?
    /// The next meeting starting between now and the end, for «Через 5 мин — …».
    @ObservationIgnored var nextMeeting: ((_ after: Date, _ before: Date) -> FocusMeeting?)?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var screenLocked = false
    @ObservationIgnored private var ticksSinceSave = 0

    func start() async {
        guard status != .running else { return }
        status = .running
        log = FocusLog()
        var saved = FocusTimer.saved() ?? FocusTimer()
        // Mely was not running: a session whose time ran out finishes silently.
        let events = saved.restore(now: Date())
        timer = saved
        for event in events { handle(event) }
        timer.save()
        registerHotKey()
        settings.changed = { [weak self] in self?.registerHotKey() }
        watchLockAndSleep()
        updateTicker()
    }

    func stop() async {
        // Off: no timer in the notch; what was worked so far is kept.
        apply { $0.stop(now: Date()) }
        ticker?.invalidate(); ticker = nil
        hotKey = nil
        settings.changed = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
        log = nil
        status = .off
    }

    // MARK: Actions

    /// ⌃⌥P: a session on the default length, or pause and go on.
    func toggle() {
        guard status == .running else { return }
        switch timer.phase {
        case .working: pause()
        case .paused: resume()
        default: start(minutes: settings.defaultMinutes)
        }
    }

    /// Starts a session; while one runs, see `replace`.
    func start(minutes: Int, task: FocusTaskRef? = nil) {
        apply { $0.start(now: Date(), duration: TimeInterval(minutes * 60), task: task) }
    }

    /// «Заменить»: the running session ends with its time counted.
    func replace(minutes: Int, task: FocusTaskRef? = nil) {
        apply { $0.replace(now: Date(), duration: TimeInterval(minutes * 60), task: task) }
    }

    func pause() { apply { $0.pause(now: Date()) } }
    func resume() { apply { $0.resume(now: Date()) } }
    func stopSession() { apply { $0.stop(now: Date()) } }
    func extend(minutes: Int) { apply { $0.extend(by: TimeInterval(minutes * 60), now: Date()) } }
    func takeBreak() { apply { [settings] in $0.takeBreak(now: Date(), rhythm: settings.rhythm) } }
    func skipBreak() { apply { $0.skipBreak() } }
    func continueFocus() { apply { $0.continue(now: Date()) } }

    // MARK: Ticking

    /// Runs `change` on the timer, handles its events, saves and starts or stops the ticker.
    private func apply(_ change: (inout FocusTimer) -> [FocusEvent]) {
        let events = change(&timer)
        for event in events { handle(event) }
        timer.save()
        ticksSinceSave = 0
        updateTicker()
    }

    /// Once a second, only while a session or a break runs.
    private func updateTicker() {
        let needed = status == .running && (timer.isRunning || timer.phase == .onBreak)
        if needed, ticker == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            ticker = t
        } else if !needed {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func tick() {
        let now = Date()
        let idle = settings.pausesWhenAway ? Self.secondsSinceInput() : nil
        var meeting: FocusMeeting?
        if settings.warnsMeetings, timer.isRunning {
            meeting = nextMeeting?(now, now.addingTimeInterval(timer.remaining(now: now)))
        }
        let events = timer.tick(now: now, idleSeconds: idle, nextMeeting: meeting, awayAfter: settings.awayAfter)
        for event in events { handle(event) }
        // The last input is saved now and then: a relaunch counts no further than it.
        ticksSinceSave += 1
        if !events.isEmpty || ticksSinceSave >= 15 {
            timer.save()
            ticksSinceSave = 0
        }
        if !events.isEmpty { updateTicker() }
    }

    private func handle(_ event: FocusEvent) {
        switch event {
        case .started:
            logger.info("focus started")
            if settings.playsStartSound { SoundEngine.shared.play(.focusStart) }
        case .finished:
            logger.info("focus finished")
            if settings.playsEndSound { SoundEngine.shared.play(.focusEnd) }
        case let .record(record):
            log?.add(record)
        case .autoPaused:
            logger.info("focus paused: away")
        default:
            break
        }
        onEvent?(event)
    }

    /// Since the last mouse or keyboard input, any app; needs no permission.
    private static func secondsSinceInput() -> TimeInterval {
        // kCGAnyInputEventType
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    // MARK: Lock, sleep, shortcut

    private func watchLockAndSleep() {
        guard observers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor (FocusIntegration) -> Void) {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { action(self) } }
            }
            observers.append((center, observer))
        }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { me in
            me.screenLocked = true
            me.apply { $0.lock(now: Date()) }
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { me in
            me.screenLocked = false
            me.apply { $0.unlock(now: Date()) }
        }
        observe(workspace, NSWorkspace.willSleepNotification) { me in me.apply { $0.lock(now: Date()) } }
        // Woken without a password: back now; with one, on the unlock.
        observe(workspace, NSWorkspace.didWakeNotification) { me in
            if !me.screenLocked { me.apply { $0.unlock(now: Date()) } }
        }
    }

    /// ⌃⌥P unless changed in the settings; registered again after a change.
    private func registerHotKey() {
        guard status == .running else { return }
        let code = settings.hotKeyCode, modifiers = settings.hotKeyModifiers
        if let hotKey, hotKey.keyCode == code, hotKey.modifiers == modifiers { return }
        hotKey = nil
        hotKey = GlobalHotKey(keyCode: code, modifiers: modifiers) { [weak self] in self?.toggle() }
    }
}
