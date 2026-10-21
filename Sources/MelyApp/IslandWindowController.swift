// Portions © 2026 Louis Raillé, MIT License — see THIRD_PARTY_NOTICES.md.
import AppKit
import SwiftUI
import MelyCore
import MelyUI
import OSLog

private let log = Logger(subsystem: "dev.mely.app", category: "island")

/// The transparent panel at the top of the screen that hosts the island. The panel never
/// moves or resizes: the black shape inside animates. Mouse events pass through except
/// over the island itself, so the menu bar and the windows below keep working.
@MainActor
final class IslandWindowController {
    let presentation: IslandPresentation
    let machine = IslandStateMachine()

    private let panel: IslandPanel
    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 0
    private var wasInIsland = false
    private var screenObserver: NSObjectProtocol?
    private var focusMonitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    private var peekTask: Task<Void, Never>?
    private var currentScreen: NSScreen?

    private static let fastPoll: TimeInterval = 1.0 / 60
    private static let nearPoll: TimeInterval = 1.0 / 20
    private static let idlePoll: TimeInterval = 1.0 / 8

    init<Compact: View, Expanded: View, Header: View>(@ViewBuilder compactLeading: () -> Compact,
                                                      compactTrailing: AnyView,
                                                      @ViewBuilder expanded: () -> Expanded,
                                                      @ViewBuilder header: () -> Header) {
        let screen = Self.targetScreen(for: Self.displayChoice)
        presentation = IslandPresentation(geometry: Self.screenGeometry(for: screen))
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: IslandPresentation.panelSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        // The island is always dark: popovers and menus opened from it follow the panel.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.hasShadow = false
        // Above the menu bar so the island covers the notch area.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isMovable = false

        let root = IslandRootView(presentation: presentation,
                                  compactLeading: compactLeading,
                                  compactTrailing: compactTrailing,
                                  expanded: expanded,
                                  header: header)
            .onTapGesture { [weak machine, weak self, presentation] in
                // A preview with a button: the whole preview is the button.
                if presentation.mode == .peek, let peek = presentation.peek, peek.actionTitle != nil {
                    if self?.lasting?.id == peek.id { self?.lasting = nil }
                    self?.onPeekAction?(peek.id)
                    presentation.peek = nil
                    presentation.mode = machine?.state == .hidden ? .hidden : .compact
                    return
                }
                // A message preview leads to its app, as a system banner does.
                if presentation.mode == .peek, let peek = presentation.peek, peek.opensApp,
                   let id = peek.appBundleId, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    // The exact chat when the owner knows how; else just the app.
                    if self?.onPeekOpen?(peek.id) != true {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
                    }
                    presentation.peek = nil
                    presentation.mode = machine?.state == .hidden ? .hidden : .compact
                    return
                }
                machine?.userInteracted()
                machine?.click()
            }
        let hosting = NSHostingView(rootView: root)
        // The panel never resizes: without this, every animation frame (Mely, the
        // equalizer) re-ran Auto Layout over the whole window, ~10% CPU for nothing.
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: IslandPresentation.panelSize)
        panel.contentView = hosting

        relocate(to: screen)
        wireMachine()
        panel.onEscape = { [weak self] in
            guard let self else { return }
            self.machine.collapse()
            self.panel.resignKey()
        }
        observeScreens()
        observeFocus()
        panel.orderFrontRegardless()
        startPolling(interval: Self.idlePoll)
    }

    // MARK: - State machine

    private func wireMachine() {
        machine.onTransition = { [weak self] _, new in
            guard let self else { return }
            // A peek on screen stays until its timer ends, unless the island opens.
            if self.presentation.mode == .peek, new == .compact || new == .hidden { return }
            self.peekTask?.cancel()
            // Folded back from the full island: a meeting reminder comes back.
            if new == .compact || new == .hidden, self.showLastingIfAny() { return }
            switch new {
            case .hidden: self.presentation.mode = .hidden
            case .compact: self.presentation.mode = self.compactMode
            case .expanded, .listening: self.presentation.mode = .expanded
            case .greeting:
                self.presentation.greetingStart = Date()
                self.presentation.mode = .greeting
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(GreetingView.duration))
                    self?.machine.greetComplete()
                }
            }
        }
    }

    // MARK: - Wings

    /// Something waits for the user: the wings stay out until it is answered.
    var wingsPinned: () -> Bool = { false }
    /// Something is going on (Claude works, music plays, a limit is near).
    var wingsLive: () -> Bool = { false } {
        didSet {
            machine.keepsCompact = { [weak self] in
                guard let self else { return false }
                return IslandWings.Mode.stored() == .whileActive && self.wingsLive()
            }
        }
    }
    private var wings = IslandWings()

    /// What the compact state shows: with wings, or just the notch (task 1.6).
    private var compactMode: IslandPresentation.Mode {
        wings.showsWings(hovering: wasInIsland, pinned: wingsPinned(), live: wingsLive(),
                         mode: IslandWings.Mode.stored()) ? .compact : .hidden
    }

    /// An event worth seeing: the island comes out with its wings for a few seconds,
    /// then shrinks back to the notch by itself.
    func flashWings() {
        wings.flash()
        machine.reveal()
        updateWings()
    }

    /// Re-checked on every poll: the flash runs out and the pointer moves without
    /// telling the state machine.
    private func updateWings() {
        // Something started (music, a turn) while the island was hidden: bring it back.
        if machine.state == .hidden, IslandWings.Mode.stored() == .whileActive, wingsLive() || wingsPinned() {
            machine.reveal()
        }
        guard machine.state == .compact,
              presentation.mode == .compact || presentation.mode == .hidden else { return }
        let target = compactMode
        guard target != presentation.mode else { return }
        presentation.mode = target
    }

    /// Shows the compact island (activity that is not an alert).
    func reveal() { machine.reveal() }

    /// The launch greeting (task 7.2): Mely drops out of the notch and says hello.
    func greet() { machine.launch() }

    /// Runs the action of a preview with a button (meeting reminder → join), by its id.
    var onPeekAction: ((String) -> Void)?
    /// Opens what a message preview points at; false lets the island just open the app.
    var onPeekOpen: ((String) -> Bool)?

    /// A meeting reminder (`PeekContent.until`): shown until the meeting starts, back after
    /// other previews and after the island folds, gone with «×» or «Подключиться».
    private var lasting: PeekContent?

    /// Puts the lasting reminder back on screen; false when there is none (or it ran out).
    @discardableResult
    private func showLastingIfAny() -> Bool {
        guard let content = lasting, let until = content.until else { return false }
        guard MeetingCountdown.isActive(until: until, now: Date()) else { lasting = nil; return false }
        guard machine.state != .expanded && machine.state != .listening else { return false }
        showPeek(content)
        return true
    }

    /// Shows a short card under the notch, then folds back to whatever the state machine says.
    /// Hovering keeps it; a click opens the full island. A reminder with `until` stays till then.
    func showPeek(_ content: PeekContent, for duration: Duration = .seconds(5)) {
        var duration = duration
        if let until = content.until {
            lasting = content
            duration = .seconds(max(1, until.timeIntervalSinceNow))
        }
        presentation.dismissPeek = { [weak self] in self?.dismissLasting() }
        guard machine.state != .expanded && machine.state != .listening else { return }
        machine.reveal()
        presentation.peek = content
        presentation.mode = .peek
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            while let self, !Task.isCancelled, self.wasInIsland {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard let self, !Task.isCancelled, self.presentation.mode == .peek else { return }
            // Another preview passed over a reminder: the reminder comes back.
            if self.lasting?.id != content.id, self.showLastingIfAny() { return }
            if self.lasting?.id == content.id { self.lasting = nil }
            self.presentation.mode = self.machine.state == .hidden ? .hidden : .compact
            self.presentation.peek = nil
        }
    }

    /// «×» on a reminder.
    private func dismissLasting() {
        lasting = nil
        peekTask?.cancel()
        guard presentation.mode == .peek else { return }
        presentation.mode = machine.state == .hidden ? .hidden : .compact
        presentation.peek = nil
    }

    /// The island on screen (AppKit coordinates): where Mely flies home to.
    var screenFrame: CGRect {
        islandRect.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
    }

    /// Mely is being carried out of the island: the panel keeps the mouse until it is let go.
    var isCarrying: () -> Bool = { false }

    /// Folds the island (Mely settled on the desktop).
    func collapse() { machine.collapse() }

    /// «×» in the header: folds and gives the keyboard back.
    func collapseFromHeader() {
        machine.collapse()
        panel.resignKey()
    }

    /// The island has the keyboard (the chat field is focused).
    var hasKeyboard: Bool { panel.isKeyWindow }

    /// Opens the island and takes the keyboard, for typing in the chat. The panel does not
    /// activate the app: the window below keeps its place.
    func expandForTyping() {
        expandForAlert()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Opens the island for something that needs the user (approval, question, alert).
    func expandForAlert() {
        machine.openedExternally()
        presentation.mode = .expanded
    }

    // MARK: - Screens

    static var displayChoice: IslandDisplayChoice {
        IslandDisplayChoice(storageValue: UserDefaults.standard.string(forKey: IslandDisplayChoice.defaultsKey) ?? "")
    }

    private func observeScreens() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.relocate(to: Self.targetScreen(for: Self.displayChoice))
            }
        }
    }

    // MARK: - Focus

    /// «Закрывать при клике мимо»: a click outside the island, or another app coming forward.
    private func observeFocus() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Clicks in other apps never reach Mely: only a global monitor sees them.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedOutside() }
        }) { focusMonitors.append(global) }
        // Mely's own windows: Settings counts as elsewhere; the island, its menus and
        // popovers, and Mely on the desktop (floating panels) do not.
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated {
                if let window = event.window, window.level == .normal { self?.clickedOutside() }
            }
            return event
        }) { focusMonitors.append(local) }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.loseFocus("app \(app?.bundleIdentifier ?? "-")") }
        }
    }

    private func loseFocus(_ reason: String) {
        let before = machine.state
        machine.focusLost()
        if machine.state != before { log.info("folded: \(reason, privacy: .public)") }
    }

    private func clickedOutside() {
        // Carrying Mely out of the island is a drag that starts inside.
        guard !isCarrying(), !screenFrame.contains(NSEvent.mouseLocation) else { return }
        loseFocus("click outside")
    }

    /// Recomputes the resting geometry for `screen` and pins the panel to its top centre.
    /// Always re-applied, even on the same screen: its menu bar or resolution may have changed.
    private func relocate(to screen: NSScreen) {
        currentScreen = screen
        presentation.geometry = Self.screenGeometry(for: screen)
        let frame = screen.frame
        let size = IslandPresentation.panelSize
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    /// Settings → «Где показывать челку» changed.
    func relocateToChosenScreen() {
        relocate(to: Self.targetScreen(for: Self.displayChoice))
    }

    /// Follow-the-mouse mode: hop to the cursor's screen while the island is not open.
    private func followMouseIfNeeded(_ mouse: NSPoint) {
        guard Self.displayChoice == .followMouse, presentation.mode != .expanded else { return }
        if let current = currentScreen, current.frame.contains(mouse) { return }
        guard let target = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
              target != currentScreen else { return }
        relocate(to: target)
    }

    static func targetScreen(for choice: IslandDisplayChoice) -> NSScreen {
        let screens = NSScreen.screens
        let mouse = NSEvent.mouseLocation
        let candidates = screens.map {
            IslandDisplayCandidate(uuid: displayUUID($0), hasNotch: $0.safeAreaInsets.top > 0,
                                   containsMouse: $0.frame.contains(mouse))
        }
        if let i = IslandDisplayResolver.index(for: choice, in: candidates) { return screens[i] }
        return screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? screens[0]
    }

    /// Stable display UUID (the NSScreenNumber can change after a reboot or a replug).
    static func displayUUID(_ screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func screenGeometry(for screen: NSScreen) -> IslandScreenGeometry {
        let visibleMenuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        // visibleFrame includes the menu bar only while it is visible; keep a small
        // resting bar when menus auto-hide or an app is in full screen.
        let menuBarHeight = visibleMenuBarHeight > 0 ? visibleMenuBarHeight : NSStatusBar.system.thickness
        return IslandScreenGeometry(
            screenWidth: screen.frame.width, safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: menuBarHeight)
    }

    // MARK: - Hover polling

    /// Polls the pointer instead of tracking areas: the panel ignores mouse events most of
    /// the time, and tracking areas do not fire on a click-through window. The rate drops to
    /// 8 Hz away from the island, so a hidden island costs next to nothing.
    private func startPolling(interval: TimeInterval) {
        pollTimer?.invalidate()
        pollInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// The island's rect in panel coordinates (AppKit, origin bottom-left).
    private var islandRect: CGRect {
        let size = presentation.islandSize
        let panelSize = IslandPresentation.panelSize
        return CGRect(x: (panelSize.width - size.width) / 2, y: panelSize.height - size.height,
                      width: size.width, height: size.height)
    }

    private func poll() {
        let mouse = NSEvent.mouseLocation
        followMouseIfNeeded(mouse)

        let pf = panel.frame
        let local = CGPoint(x: mouse.x - pf.minX, y: mouse.y - pf.minY)
        // Without a notch the resting bar must not grab clicks meant for the window below.
        let hoverRect = !presentation.geometry.hasNotch && presentation.mode != .expanded
            ? islandRect : islandRect.insetBy(dx: -6, dy: -6)
        let inIsland = hoverRect.contains(local)
        let carrying = isCarrying()

        if !carrying, panel.ignoresMouseEvents == inIsland {
            panel.ignoresMouseEvents = !inIsland
        }

        let previously = wasInIsland
        wasInIsland = inIsland
        if inIsland && !previously { machine.mouseEntered() }
        if !inIsland && previously { machine.mouseLeft() }
        updateWings()

        let island = islandRect.offsetBy(dx: pf.minX, dy: pf.minY)
        let near = island.insetBy(dx: -200, dy: -160).contains(mouse)
        let inBand = pf.insetBy(dx: -120, dy: -120).contains(mouse)
        let busy = presentation.mode == .expanded || near
        let wanted = busy ? Self.fastPoll : inBand ? Self.nearPoll : Self.idlePoll
        if wanted != pollInterval { startPolling(interval: wanted) }
    }
}

/// Borderless panel allowed to sit over the menu bar and the notch.
final class IslandPanel: NSPanel {
    /// Escape, while the island has the keyboard (the chat field).
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
    override var canBecomeMain: Bool { false }

    /// Keep macOS from pushing the panel below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
