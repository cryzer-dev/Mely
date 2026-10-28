import EventKit
import Observation
import OSLog
import MelyCore

private let log = Logger(subsystem: "dev.mely.app", category: "reminders")

/// Tasks from Apple Reminders (EventKit): the "Задачи" tab, today's tasks under the
/// agenda, due reminders under the notch, «В задачи» from a session.
@MainActor
@Observable
final class RemindersIntegration: Integration {
    let id = "reminders"
    let displayName = "Задачи"
    let summary = "Задачи из Напоминаний: на сегодня, быстрое добавление, перенос и отметка"
    let requiredPermissions: [SystemPermission] = [.reminders]
    private(set) var status: IntegrationStatus = .off

    /// Its own store: switched off, the integration holds nothing (the calendar has its own).
    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var timer: Timer?

    func start() async {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            status = .needsPermission(.reminders)
            // Granted later in System Settings: try again on the next tick.
            scheduleTimer()
            return
        }
        if store == nil { store = EKEventStore() }
        status = .running
        log.info("started")
        scheduleTimer()
    }

    func stop() async {
        timer?.invalidate(); timer = nil
        store = nil
        status = .off
    }

    /// Every 30 s: access may have been granted.
    private func scheduleTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.status == .needsPermission(.reminders),
                      EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
                Task { await self.start() }
            }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
