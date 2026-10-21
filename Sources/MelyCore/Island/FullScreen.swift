import Foundation
import CoreGraphics

/// «Полноэкранные приложения»: what Mely does on a screen taken by a full-screen app
/// (a video, a game, a presentation).
public enum FullScreenMode: String, CaseIterable, Identifiable, Sendable {
    /// As if nothing were full screen.
    case normal
    /// Hidden and quiet; permission requests and Claude's questions still come through.
    case importantOnly
    /// Nothing at all; requests wait in the island until the screen is free.
    case doNotDisturb

    public static let `default` = FullScreenMode.importantOnly
    public static let defaultsKey = "islandFullScreenMode"
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .normal: "Показывать всё"
        case .importantOnly: "Только разрешения и вопросы"
        case .doNotDisturb: "Не беспокоить"
        }
    }

    /// May this show (and sound) over a full-screen app? `isRequest`: a permission request
    /// or a question of Claude's, which blocks its work until answered.
    public func allows(isRequest: Bool) -> Bool {
        switch self {
        case .normal: true
        case .importantOnly: isRequest
        case .doNotDisturb: false
        }
    }
}

/// Is a screen taken by a full-screen app? Read from the on-screen window list, which
/// needs no screen recording permission for bounds and owners.
public enum FullScreenDetector {
    public struct Window: Equatable, Sendable {
        public let pid: Int32
        public let layer: Int
        /// Global coordinates, origin at the top left of the main screen (as CoreGraphics).
        public let bounds: CGRect

        public init(pid: Int32, layer: Int, bounds: CGRect) {
            self.pid = pid
            self.layer = layer
            self.bounds = bounds
        }
    }

    /// Entries of `CGWindowListCopyWindowInfo` that carry what the rule needs.
    public static func windows(from list: [[String: Any]]) -> [Window] {
        list.compactMap { info in
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return nil }
            return Window(pid: pid, layer: layer, bounds: bounds)
        }
    }

    /// Level of the menu bar's status items (`kCGStatusWindowLevel`).
    public static let statusItemLayer = 25

    /// An ordinary window of another app covers the screen. Either all of it, or, on a
    /// screen with a notch, all but the strip beside the camera (`topInset`): macOS keeps
    /// full-screen windows out of it. A window stretched under the menu bar has the same
    /// size there, so that case also needs the menu bar's status items gone from the screen.
    /// Any app, not only the active one: the full-screen space stays on its screen while
    /// the user works on another display.
    /// - Parameter screen: the screen in CoreGraphics coordinates (`cgFrame`).
    public static func isFullScreen(_ windows: [Window], screen: CGRect, topInset: CGFloat = 0, ownPid: Int32) -> Bool {
        func covers(_ w: Window, _ area: CGRect) -> Bool {
            abs(w.bounds.minX - area.minX) <= 2 && abs(w.bounds.minY - area.minY) <= 2
                && abs(w.bounds.width - area.width) <= 2 && abs(w.bounds.height - area.height) <= 2
        }
        let apps = windows.filter { $0.layer == 0 && $0.pid != ownPid }
        if apps.contains(where: { covers($0, screen) }) { return true }
        guard topInset > 0 else { return false }
        let belowNotch = CGRect(x: screen.minX, y: screen.minY + topInset, width: screen.width, height: screen.height - topInset)
        let menuBarShown = windows.contains { $0.layer == statusItemLayer && $0.bounds.intersects(screen) }
        return !menuBarShown && apps.contains { covers($0, belowNotch) }
    }

    /// An AppKit screen frame (origin bottom left) in CoreGraphics coordinates.
    /// - Parameter mainHeight: height of the screen at the origin (`NSScreen.screens[0]`).
    public static func cgFrame(_ frame: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
