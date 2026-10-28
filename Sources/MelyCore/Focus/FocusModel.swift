import Foundation
import Observation

/// What the notch shows of the focus: the timer, set by `FocusIntegration`, read by the views.
@MainActor
@Observable
public final class FocusModel {
    public var timer: FocusTimer

    public init(timer: FocusTimer = FocusTimer()) {
        self.timer = timer
    }
}

public extension FocusTimer {
    /// Something to show in the wing: a session (running or paused) or a break.
    var isLive: Bool { isRunning || phase == .onBreak }

    /// The countdown: «18:42», «1:05:00»; a started second counts whole, so 0:00 is the end.
    static func clock(_ time: TimeInterval) -> String {
        let total = Int(max(0, time).rounded(.up))
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
