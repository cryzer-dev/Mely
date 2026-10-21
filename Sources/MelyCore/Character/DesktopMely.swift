import Foundation
import CoreGraphics
import Observation

/// Where Mely is: in the notch, or out on the desktop (task 6.8). The island reads it to
/// leave Mely's spot empty while it is away.
@MainActor
@Observable
public final class DesktopPresence {
    public var isOnDesktop = false
    /// Being carried from the island right now.
    public var isDragging = false
    public init() {}
}

/// Mely's trips between the notch and the desktop:
/// approvals and questions call it back to the notch, and it flies out again once they
/// are answered.
public struct DesktopMelyMachine: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// In the notch; not on the desktop.
        case home
        /// Flying from the notch to its spot.
        case flyingOut
        /// On the desktop.
        case onDesktop
        /// Back in the notch for an alert; returns when it is answered.
        case awayForAlert
    }

    /// What the controller must do after an event.
    public enum Action: Equatable, Sendable {
        case none
        /// Fly from the notch to the saved spot.
        case flyOut
        /// Fly into the notch and stay there (the user brought it home).
        case flyHome
        /// Fly into the notch for an alert; the desktop spot is kept.
        case retract
    }

    public private(set) var phase: Phase
    /// The user left Mely on the desktop: kept across launches.
    public private(set) var wantsDesktop: Bool

    public init(wantsDesktop: Bool = false) {
        phase = .home
        self.wantsDesktop = wantsDesktop
    }

    /// At launch: back to the desktop if it was left there, unless an alert waits.
    public mutating func launched(alert: Bool) -> Action {
        guard wantsDesktop, phase == .home else { return .none }
        if alert { phase = .awayForAlert; return .none }
        phase = .flyingOut
        return .flyOut
    }

    /// Dropped on an empty spot: it lives there now.
    public mutating func dropped() {
        wantsDesktop = true
        phase = .onDesktop
    }

    /// The flight out ended; an alert that came meanwhile sends it straight back.
    public mutating func landed(alert: Bool) -> Action {
        guard phase == .flyingOut || phase == .onDesktop else { return .none }
        phase = .onDesktop
        if alert { phase = .awayForAlert; return .retract }
        return .none
    }

    public mutating func alertChanged(active: Bool) -> Action {
        switch (phase, active) {
        case (.onDesktop, true):
            phase = .awayForAlert
            return .retract
        case (.awayForAlert, false):
            phase = .flyingOut
            return .flyOut
        default:
            return .none
        }
    }

    /// Double click, dropped on the notch, the menu or ⌃⌥D.
    public mutating func sentHome() -> Action {
        wantsDesktop = false
        switch phase {
        case .onDesktop, .flyingOut:
            phase = .home
            return .flyHome
        case .awayForAlert, .home:
            phase = .home
            return .none
        }
    }

    /// ⌃⌥D: out if home, home if out.
    public mutating func toggled(alert: Bool) -> Action {
        if wantsDesktop { return sentHome() }
        wantsDesktop = true
        return launched(alert: alert)
    }
}

/// Geometry and timing of the desktop Mely (AppKit coordinates, y up).
public enum DesktopMelyLogic {
    public static let panelSize: CGFloat = 120
    /// Asleep after two minutes without Claude working…
    public static let sleepTimeout: TimeInterval = 120
    /// …while the pointer is not close.
    public static let sleepMouseDistance: CGFloat = 150
    public static let margin: CGFloat = 24
    /// The clickable round body, as a share of the panel; around it clicks pass through.
    public static let bodyRadius: CGFloat = 0.3

    public static func shouldSleep(idleFor: TimeInterval, mouseDistance: CGFloat) -> Bool {
        idleFor > sleepTimeout && mouseDistance >= sleepMouseDistance
    }

    /// Whether a point inside the panel (local, y up) is on Mely rather than the empty corners.
    public static func isOverBody(_ local: CGPoint, panelSize: CGFloat = panelSize) -> Bool {
        let r = panelSize * bodyRadius
        let dx = local.x - panelSize / 2
        let dy = local.y - panelSize / 2
        return dx * dx + dy * dy <= r * r
    }

    /// Keeps the panel inside the screen's visible area, `margin` away from its edges.
    public static func clamp(_ origin: CGPoint, panelSize: CGFloat = panelSize, visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: min(max(origin.x, visibleFrame.minX + margin), visibleFrame.maxX - panelSize - margin),
                y: min(max(origin.y, visibleFrame.minY + margin), visibleFrame.maxY - panelSize - margin))
    }

    /// First time out: bottom right of the screen.
    public static func defaultOrigin(visibleFrame: CGRect, panelSize: CGFloat = panelSize) -> CGPoint {
        CGPoint(x: visibleFrame.maxX - panelSize - margin, y: visibleFrame.minY + margin)
    }

    /// Quartz window bounds (y down from the top of the main screen) to AppKit (y up).
    public static func appKitRect(fromQuartz r: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: mainScreenHeight - r.maxY, width: r.width, height: r.height)
    }
}
