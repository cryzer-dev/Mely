import AppKit
import TelemetryDeck
import MelyCore
import OSLog

private let telemetryLog = Logger(subsystem: "dev.mely.app", category: "telemetry")

/// Anonymous usage statistics through TelemetryDeck (openspec usage-telemetry): the SDK's
/// own signal at each launch (versions of Mely and macOS), and a day's counts the next day.
/// Off in the settings: nothing is sent and the counts are forgotten.
@MainActor
final class Telemetry {
    /// Public by design: it only says which app a signal belongs to.
    static let appID = "C37C8DEB-8B13-444C-9563-95E3C10EEBF5"

    let settings = TelemetrySettings()
    private let counters = UsageCounters()
    /// Ids of the integrations switched on, sent with the counts.
    var integrations: () -> [String] = { [] }
    private var started = false
    private var wakeObserver: NSObjectProtocol?

    func start() {
        settings.changed = { [weak self] in self?.apply() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                                         queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(self?.counters.rollover()) }
        }
        apply()
        send(counters.rollover())
    }

    func count(_ counter: UsageCounter) {
        guard settings.isOn else { return }
        send(counters.bump(counter))
    }

    private func apply() {
        if settings.isOn {
            guard !started else { return }
            let config = TelemetryDeck.Config(appID: Self.appID)
            // MelyDev's signals stay apart from the releases'.
            config.testMode = AppInfo.isDevBuild
            // Session lengths would be written to UserDefaults every second: not needed.
            config.sessionStatsEnabled = false
            // MelyDev logs what goes out and what comes back, readable in Console.
            if AppInfo.isDevBuild {
                config.logHandler = LogHandler(logLevel: .debug) { _, message in
                    telemetryLog.debug("\(message, privacy: .public)")
                }
            }
            // Sends "TelemetryDeck.Session.started": the launch.
            TelemetryDeck.initialize(config: config)
            started = true
        } else {
            counters.reset()
            guard started else { return }
            TelemetryDeck.terminate()
            started = false
        }
    }

    private func send(_ summary: UsageSummary?) {
        guard started, let summary else { return }
        for signal in summary.signals(integrations: integrations()) {
            TelemetryDeck.signal(signal.name, parameters: signal.parameters, floatValue: signal.value)
        }
    }
}
