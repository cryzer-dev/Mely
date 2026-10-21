import AppKit
import OSLog
import MelyCore

private let log = Logger(subsystem: "dev.mely.app", category: "island")

/// Which screens a full-screen app has taken. Re-read when the space, the active app or
/// the screens change, and every couple of seconds (a video goes full screen inside its
/// own app without any of those).
@MainActor
final class FullScreenWatcher {
    /// Display ids of the taken screens.
    private(set) var taken: Set<CGDirectDisplayID> = []
    /// Called on the main actor after `taken` changed.
    var onChange: () -> Void = {}
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    /// Seen once, waiting to be confirmed.
    private var pending: Set<CGDirectDisplayID>?

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        let update: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers = [
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: update),
            workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: update),
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                   object: nil, queue: .main, using: update),
        ]
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    func covers(_ screen: NSScreen?) -> Bool {
        guard let id = screen.flatMap(Self.displayId) else { return false }
        return taken.contains(id)
    }

    func refresh() {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let windows = FullScreenDetector.windows(from: list)
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let me = ProcessInfo.processInfo.processIdentifier
        let now = Set(NSScreen.screens.compactMap { screen -> CGDirectDisplayID? in
            let frame = FullScreenDetector.cgFrame(screen.frame, mainHeight: mainHeight)
            return FullScreenDetector.isFullScreen(windows, screen: frame, topInset: screen.safeAreaInsets.top, ownPid: me)
                ? Self.displayId(screen) : nil
        })
        guard now != taken else { pending = nil; return }
        // A screen freed shows at once; a screen taken must stay taken for a moment:
        // the animation into or out of full screen passes over a screen for a split second.
        if now.isSubset(of: taken) || pending == now {
            pending = nil
        } else {
            pending = now
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                MainActor.assumeIsolated { if self?.pending == now { self?.refresh() } }
            }
            return
        }
        taken = now
        log.info("full-screen displays: \(now.map(String.init).sorted().joined(separator: ","), privacy: .public)")
        onChange()
    }

    static func displayId(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
