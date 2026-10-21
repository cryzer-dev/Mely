// Portions © 2026 Louis Raillé, MIT License — see THIRD_PARTY_NOTICES.md.
import AppKit
import SwiftUI
import Observation
import MelyCore
import MelyUI
import OSLog

private let log = Logger(subsystem: "dev.mely.app", category: "desktop")

/// What the desktop Mely shows besides the pose of the moment.
@MainActor
@Observable
final class DesktopMelyModel {
    /// Asleep: nothing going on for two minutes and the pointer away.
    var asleep = false
    /// The pointer is on it: it grows a little.
    var hovered = false
    /// Carried: it shows this pose instead (glad to be picked up).
    var carried: CharacterPose?
}

/// Mely out of the notch (task 6.8):
/// - pulled out of the island and dropped on another app's window, it asks Claude about
///   that window: the chat opens with the window attached;
/// - dropped anywhere else, it lives there, over the windows, and comes back after a relaunch;
/// - on the desktop: a click pokes it, a double click sends it home, a right click opens
///   its menu, dragging moves it (onto a window: asks about it, onto the notch: home);
/// - an approval or a question calls it back to the notch, where the card is; once
///   answered it flies back out;
/// - ⌃⌥D sends it out or brings it home.
@MainActor
final class DesktopMelyController {
    let presence: DesktopPresence
    /// The island's rect on screen (AppKit), for "dropped on the notch" and flights.
    var islandFrame: () -> CGRect = { .zero }
    /// An approval or a question waits.
    var alertActive: () -> Bool = { false }
    /// Claude is busy somewhere: keeps Mely awake.
    var busy: () -> Bool = { false }
    /// Dropped on a window: ask about it.
    var askAbout: (NSRunningApplication, CGRect) -> Void = { _, _ in }
    /// Right click → «Персонаж…».
    var openSettings: () -> Void = {}
    /// The island folds when Mely settles on the desktop.
    var collapseIsland: () -> Void = {}

    private let makeCharacter: (DesktopMelyModel) -> AnyView
    private var machine: DesktopMelyMachine
    private var panel: NSPanel?
    private let model = DesktopMelyModel()
    private var ghost: NSPanel?
    private let ghostModel = DesktopMelyModel()
    private var highlight: NSPanel?
    private var highlightTarget: CGRect?
    private var lastHighlightScan: TimeInterval = 0
    private var dragMonitors: [Any] = []
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var lastBusy = Date()
    private var lastAlert = false
    private var hotKey: GlobalHotKey?
    private var observers: [NSObjectProtocol] = []

    private static let enabledKey = "melyOnDesktop"
    private static let xKey = "melyDesktopX"
    private static let yKey = "melyDesktopY"
    private static let ghostSize: CGFloat = 72
    private var size: CGFloat { DesktopMelyLogic.panelSize }

    init(presence: DesktopPresence, makeCharacter: @escaping (DesktopMelyModel) -> AnyView) {
        self.presence = presence
        self.makeCharacter = makeCharacter
        machine = DesktopMelyMachine(wantsDesktop: UserDefaults.standard.bool(forKey: Self.enabledKey))
        ghostModel.carried = .happy
        hotKey = GlobalHotKey(keyCode: kVK_ANSI_D_Code) { [weak self] in self?.toggle() }
        observeScreenSleep()
        startTimer(interval: 0.25)
    }

    /// At launch: back to its spot if it was left on the desktop.
    func start() {
        lastAlert = alertActive()
        run(machine.launched(alert: lastAlert))
        presence.isOnDesktop = isOut
    }

    /// Out on the desktop or on its way there; called back for an alert, it is in the notch.
    private var isOut: Bool { machine.phase == .onDesktop || machine.phase == .flyingOut }

    // MARK: - Carried out of the island

    /// The island's character view hands these over (`CharacterDrag`).
    func drag() -> CharacterDrag {
        CharacterDrag(isAway: presence.isOnDesktop,
                      began: { [weak self] in self?.beginCarry(at: $0) },
                      moved: { [weak self] in self?.carry(to: $0) },
                      ended: { [weak self] in self?.endCarry(at: $0) },
                      callHome: { [weak self] in self?.sendHome() })
    }

    private func beginCarry(at point: CGPoint) {
        guard ghost == nil, machine.phase == .home else { return }
        presence.isDragging = true
        let s = Self.ghostSize
        let panel = makePanel(level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4), model: ghostModel)
        panel.setFrame(NSRect(x: point.x - s / 2, y: point.y - s / 2, width: s, height: s), display: false)
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
        ghost = panel
        // The view under the press may vanish (the island folds): mouse-up is caught here too.
        let up = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            MainActor.assumeIsolated { self?.endCarry(at: NSEvent.mouseLocation) }
            return event
        }
        let globalUp = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.endCarry(at: NSEvent.mouseLocation) }
        }
        dragMonitors = [up, globalUp].compactMap { $0 }
        startTimer(interval: 1.0 / 60)
    }

    private func carry(to point: CGPoint) {
        guard let ghost else { return }
        let s = Self.ghostSize
        ghost.setFrameOrigin(NSPoint(x: point.x - s / 2, y: point.y - s / 2))
        updateHighlight(at: point)
    }

    private func endCarry(at point: CGPoint) {
        guard let ghostPanel = ghost else { return }
        ghost = nil
        presence.isDragging = false
        dragMonitors.forEach(NSEvent.removeMonitor)
        dragMonitors = []
        hideHighlight()
        if overIsland(point) {
            fade(ghostPanel)
        } else if let target = WindowContext.window(at: point) {
            fade(ghostPanel)
            SoundEngine.shared.play(.pop)
            askAbout(target.app, target.frame)
        } else {
            ghostPanel.close()
            settle(at: point)
        }
        adjustTimer()
    }

    /// Dropped on an empty spot: it lives there now.
    private func settle(at point: CGPoint) {
        machine.dropped()
        presence.isOnDesktop = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        let panel = makeDesktopPanel()
        let s = Self.ghostSize
        panel.setFrame(NSRect(x: point.x - s / 2, y: point.y - s / 2, width: s, height: s), display: false)
        panel.orderFrontRegardless()
        let origin = clamp(NSPoint(x: point.x - size / 2, y: point.y - size / 2))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            // A small overshoot: it lands with a bounce.
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.17, 0.67, 0.38, 1.3)
            panel.animator().setFrame(NSRect(origin: origin, size: CGSize(width: size, height: size)), display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.save(origin) }
        }
        self.panel = panel
        SoundEngine.shared.play(.pop)
        collapseIsland()
        lastAlert = alertActive()
        run(machine.landed(alert: lastAlert))
    }

    // MARK: - Trips

    private func run(_ action: DesktopMelyMachine.Action) {
        switch action {
        case .none: break
        case .flyOut: flyOut()
        case .flyHome: flyIn(forGood: true)
        case .retract: flyIn(forGood: false)
        }
        presence.isOnDesktop = isOut
        adjustTimer()
    }

    /// From the notch to its saved spot.
    private func flyOut() {
        panel?.close()
        let panel = makeDesktopPanel()
        let notch = islandFrame()
        let s: CGFloat = 40
        panel.setFrame(NSRect(x: notch.midX - s / 2, y: notch.maxY - s, width: s, height: s), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        let target = savedOrigin()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(NSRect(origin: target, size: CGSize(width: size, height: size)), display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lastAlert = self.alertActive()
                self.run(self.machine.landed(alert: self.lastAlert))
            }
        }
        self.panel = panel
    }

    /// Into the notch: for good (home), or for an alert, keeping its spot for the way back.
    private func flyIn(forGood: Bool) {
        guard let panel else { return }
        self.panel = nil
        if forGood { UserDefaults.standard.set(false, forKey: Self.enabledKey) }
        let notch = islandFrame()
        let s: CGFloat = 40
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(NSRect(x: notch.midX - s / 2, y: notch.maxY - s, width: s, height: s), display: true)
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.close() }
        }
        if forGood { SoundEngine.shared.play(.home) }
    }

    func sendHome() {
        run(machine.sentHome())
    }

    func toggle() {
        guard ghost == nil else { return }
        run(machine.toggled(alert: alertActive()))
        if machine.wantsDesktop { UserDefaults.standard.set(true, forKey: Self.enabledKey) }
    }

    // MARK: - On the desktop

    private func makeDesktopPanel() -> NSPanel {
        let panel = makePanel(level: .floating, model: model)
        let host = panel.contentView as! DesktopMelyHostView
        host.onClick = { [weak self] count in self?.clicked(count) }
        host.onDragMoved = { [weak self] in self?.updateHighlight(at: $0) }
        host.onDragEnded = { [weak self] start, point in self?.movedOnDesktop(from: start, to: point) }
        host.onMenu = { [weak self] event in self?.showMenu(event) }
        model.asleep = false
        lastBusy = Date()
        return panel
    }

    private func makePanel(level: NSWindow.Level, model: DesktopMelyModel) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isMovable = false
        let host = DesktopMelyHostView(content: makeCharacter(model))
        panel.contentView = host
        return panel
    }

    private func clicked(_ count: Int) {
        if count >= 2 {
            sendHome()
        } else {
            model.asleep = false
            lastBusy = Date()
            (panel?.contentView as? DesktopMelyHostView)?.poke()
            SoundEngine.shared.play(.poke)
        }
    }

    /// Moved on the desktop: onto the notch → home; onto a window → ask about it and back
    /// to where it was; elsewhere → its new spot.
    private func movedOnDesktop(from start: CGPoint, to point: CGPoint) {
        hideHighlight()
        guard let panel else { return }
        if overIsland(point) {
            sendHome()
        } else if let target = WindowContext.window(at: point) {
            panel.setFrameOrigin(start)
            SoundEngine.shared.play(.pop)
            askAbout(target.app, target.frame)
        } else {
            let origin = clamp(panel.frame.origin)
            panel.setFrameOrigin(origin)
            save(origin)
        }
    }

    private func showMenu(_ event: NSEvent) {
        guard let view = panel?.contentView else { return }
        let menu = NSMenu()
        menu.addItem(MenuAction("Вернуть в челку") { [weak self] in self?.sendHome() }.item)
        menu.addItem(MenuAction("Персонаж…") { [weak self] in self?.openSettings() }.item)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    // MARK: - Polling: click-through, hover, sleep, alerts

    private func startTimer(interval: TimeInterval) {
        timer?.invalidate()
        timerInterval = interval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = interval / 4
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Fast while the pointer is close or Mely is carried, slow otherwise.
    private func adjustTimer() {
        let mouse = NSEvent.mouseLocation
        let close = panel.map { $0.frame.insetBy(dx: -200, dy: -200).contains(mouse) } ?? false
        let wanted = ghost != nil ? 1.0 / 60 : close ? 1.0 / 30 : 0.25
        if wanted != timerInterval { startTimer(interval: wanted) }
    }

    private func tick() {
        if let ghost {
            // The press may have lost its view: follow the pointer from here.
            let mouse = NSEvent.mouseLocation
            if ghost.frame.midX != mouse.x || ghost.frame.midY != mouse.y { carry(to: mouse) }
            return
        }
        let alert = alertActive()
        if alert != lastAlert {
            lastAlert = alert
            run(machine.alertChanged(active: alert))
        }
        guard let panel, machine.phase == .onDesktop else { return }
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let local = CGPoint(x: (mouse.x - frame.minX) * size / max(frame.width, 1),
                            y: (mouse.y - frame.minY) * size / max(frame.height, 1))
        let host = panel.contentView as? DesktopMelyHostView
        let over = DesktopMelyLogic.isOverBody(local) || host?.isDragging == true
        if panel.ignoresMouseEvents == over {
            panel.ignoresMouseEvents = !over
            log.debug("takes mouse: \(over)")
        }
        let hovered = over && host?.isDragging != true
        if model.hovered != hovered { model.hovered = hovered }
        if busy() { lastBusy = Date() }
        let asleep = DesktopMelyLogic.shouldSleep(idleFor: Date().timeIntervalSince(lastBusy),
                                                  mouseDistance: hypot(mouse.x - frame.midX, mouse.y - frame.midY))
        if model.asleep != asleep { model.asleep = asleep }
        adjustTimer()
    }

    // MARK: - Window highlight while carried

    private func updateHighlight(at point: CGPoint) {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastHighlightScan > 0.08 else { return }
        lastHighlightScan = now
        let target = overIsland(point) ? nil : WindowContext.window(at: point)?.frame
        guard target != highlightTarget else { return }
        highlightTarget = target
        guard let target else { hideHighlight(); return }
        let panel = highlight ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            let view = NSView()
            view.wantsLayer = true
            view.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
            view.layer?.borderWidth = 3
            view.layer?.cornerRadius = 12
            view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            p.contentView = view
            highlight = p
            return p
        }()
        panel.setFrame(target.insetBy(dx: -2, dy: -2), display: true)
        panel.orderFrontRegardless()
        // Mely stays on top of the frame.
        (ghost ?? self.panel)?.orderFrontRegardless()
    }

    private func hideHighlight() {
        highlight?.orderOut(nil)
        highlightTarget = nil
    }

    // MARK: - Helpers

    private func overIsland(_ point: CGPoint) -> Bool {
        islandFrame().insetBy(dx: -24, dy: -24).contains(point)
    }

    private func fade(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.close() }
        }
    }

    private func clamp(_ origin: NSPoint) -> NSPoint {
        let center = CGPoint(x: origin.x + size / 2, y: origin.y + size / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
        return DesktopMelyLogic.clamp(origin, visibleFrame: screen.visibleFrame)
    }

    private func save(_ origin: NSPoint) {
        UserDefaults.standard.set(Double(origin.x), forKey: Self.xKey)
        UserDefaults.standard.set(Double(origin.y), forKey: Self.yKey)
    }

    private func savedOrigin() -> NSPoint {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.xKey) != nil else {
            return DesktopMelyLogic.defaultOrigin(visibleFrame: (NSScreen.main ?? NSScreen.screens[0]).visibleFrame)
        }
        return clamp(NSPoint(x: defaults.double(forKey: Self.xKey), y: defaults.double(forKey: Self.yKey)))
    }

    /// Set by the app: Mely stays off a screen a full-screen app took (`FullScreenMode`).
    var yieldsTo: (NSScreen?) -> Bool = { _ in false }

    /// The full-screen screens or the setting changed.
    func fullScreenChanged() {
        guard let panel else { return }
        let hide = yieldsTo(panel.screen)
        guard hide != (panel.alphaValue == 0) else { return }
        panel.alphaValue = hide ? 0 : 1
        panel.ignoresMouseEvents = hide
    }

    /// Hidden while the screen sleeps or is locked: nothing to draw for nobody.
    private func observeScreenSleep() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let hide: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.orderOut(nil) }
        }
        let show: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.orderFrontRegardless() }
        }
        observers = [
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: hide),
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: show),
            distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main, using: hide),
            distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: show),
        ]
    }
}

private let kVK_ANSI_D_Code = 0x02

/// The desktop panel's content: Mely, and the mouse handling around it.
final class DesktopMelyHostView: NSView {
    var onClick: (Int) -> Void = { _ in }
    var onDragMoved: (CGPoint) -> Void = { _ in }
    /// Where the panel was, and where the pointer let go.
    var onDragEnded: (CGPoint, CGPoint) -> Void = { _, _ in }
    var onMenu: (NSEvent) -> Void = { _ in }
    private(set) var isDragging = false
    private var pressedAt: CGPoint?
    private var originAtPress: CGPoint = .zero
    private var pendingClick: DispatchWorkItem?

    init(content: AnyView) {
        super.init(frame: .zero)
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        autoresizesSubviews = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        subviews.first?.frame = bounds
    }

    /// The whole panel handles the mouse; the controller lets clicks through around the body.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressedAt = NSEvent.mouseLocation
        originAtPress = window?.frame.origin ?? .zero
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressedAt, let window else { return }
        let mouse = NSEvent.mouseLocation
        if !isDragging {
            guard hypot(mouse.x - start.x, mouse.y - start.y) > 3 else { return }
            isDragging = true
            pendingClick?.cancel()
        }
        window.setFrameOrigin(NSPoint(x: originAtPress.x + mouse.x - start.x, y: originAtPress.y + mouse.y - start.y))
        onDragMoved(mouse)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedAt = nil; isDragging = false }
        if isDragging {
            onDragEnded(originAtPress, NSEvent.mouseLocation)
            return
        }
        pendingClick?.cancel()
        if event.clickCount >= 2 {
            onClick(2)
        } else {
            // Wait out a double click before poking.
            let work = DispatchWorkItem { [weak self] in self?.onClick(1) }
            pendingClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onMenu(event)
    }

    /// The same squash and hop as a click on the island's Mely.
    func poke() {
        func find(_ view: NSView) -> MelyCharacterView? {
            if let mely = view as? MelyCharacterView { return mely }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        find(self)?.poke()
    }
}

/// A menu item running a closure.
private final class MenuAction: NSObject {
    let action: () -> Void
    let item: NSMenuItem

    init(_ title: String, action: @escaping () -> Void) {
        self.action = action
        item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
        super.init()
        item.target = self
        item.representedObject = self
    }

    @objc private func run() { action() }
}
