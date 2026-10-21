import AppKit
import ApplicationServices
import MelyCore

/// What the user is looking at when the chat opens:
/// the front app, its window title through Accessibility, a browser's page through
/// AppleScript. Each part is optional: without a permission it is just left out.
enum WindowContext {
    /// Chromium browsers share one dictionary; Safari has its own.
    private static let urlScripts: [String: String] = [
        "com.apple.Safari": "tell application id \"com.apple.Safari\" to return URL of current tab of front window",
        "com.google.Chrome": chromium("com.google.Chrome"),
        "company.thebrowser.Browser": chromium("company.thebrowser.Browser"),
        "com.microsoft.edgemac": chromium("com.microsoft.edgemac"),
        "com.brave.Browser": chromium("com.brave.Browser"),
        "ru.yandex.desktop.yandex-browser": chromium("ru.yandex.desktop.yandex-browser"),
    ]

    private static func chromium(_ id: String) -> String {
        "tell application id \"\(id)\" to return URL of active tab of front window"
    }

    /// The front app is read now (before the island takes the keyboard); the page address
    /// arrives later, off the main thread, since AppleScript may wait on a permission prompt.
    @MainActor
    static func capture(_ done: @escaping @MainActor (ChatContext?) -> Void) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let name = app.localizedName else { done(nil); return }
        let title = windowTitle(app.processIdentifier)
        guard let id = app.bundleIdentifier, let script = urlScripts[id] else {
            done(ChatContext(appName: name, windowTitle: title, url: nil))
            return
        }
        Task.detached {
            let url = run(script)
            await MainActor.run { done(ChatContext(appName: name, windowTitle: title, url: url)) }
        }
    }

    /// An app's window under a screen point (AppKit coordinates), topmost first: where Mely
    /// was dropped. Menus, the Dock and our own panels are skipped.
    @MainActor
    static func window(at point: CGPoint) -> (app: NSRunningApplication, frame: CGRect)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let me = ProcessInfo.processInfo.processIdentifier
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let quartz = CGRect(dictionaryRepresentation: bounds),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me else { continue }
            let frame = DesktopMelyLogic.appKitRect(fromQuartz: quartz, mainScreenHeight: mainHeight)
            guard frame.contains(point), frame.width > 80, frame.height > 60 else { continue }
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { return nil }
            return (app, frame)
        }
        return nil
    }

    /// The context of a window Mely was dropped on: its app, its title, a browser's page.
    @MainActor
    static func capture(app: NSRunningApplication, frame: CGRect, _ done: @escaping @MainActor (ChatContext?) -> Void) {
        guard let name = app.localizedName else { done(nil); return }
        let title = windowTitle(app.processIdentifier, frame: frame)
        guard let id = app.bundleIdentifier, let script = urlScripts[id] else {
            done(ChatContext(appName: name, windowTitle: title, url: nil))
            return
        }
        Task.detached {
            let url = run(script)
            await MainActor.run { done(ChatContext(appName: name, windowTitle: title, url: url)) }
        }
    }

    /// The title of the app's window at `frame` (AppKit coordinates), else of its focused one.
    private static func windowTitle(_ pid: pid_t, frame: CGRect) -> String {
        guard AXIsProcessTrusted() else { return "" }
        let app = AXUIElementCreateApplication(pid)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
              let windows = windows as? [AXUIElement] else { return windowTitle(pid) }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        for window in windows {
            var position: CFTypeRef?
            var size: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position)
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size)
            var origin = CGPoint.zero
            var extent = CGSize.zero
            guard let position, let size,
                  AXValueGetValue(position as! AXValue, .cgPoint, &origin),
                  AXValueGetValue(size as! AXValue, .cgSize, &extent) else { continue }
            let rect = DesktopMelyLogic.appKitRect(fromQuartz: CGRect(origin: origin, size: extent), mainScreenHeight: mainHeight)
            guard abs(rect.minX - frame.minX) < 2, abs(rect.minY - frame.minY) < 2,
                  abs(rect.width - frame.width) < 2 else { continue }
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            return title as? String ?? ""
        }
        return windowTitle(pid)
    }

    private static func windowTitle(_ pid: pid_t) -> String {
        guard AXIsProcessTrusted() else { return "" }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return "" }
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)
        return title as? String ?? ""
    }

    /// `osascript` with a short timeout: a browser that hangs never holds the chat.
    private static func run(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { process.terminate(); return nil }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("http") ? text : nil
    }
}
