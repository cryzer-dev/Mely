import AppKit
import MelyCore

/// "Открыть": brings the session's app forward, on the right project or tab.
@MainActor
enum HostActivator {
    @discardableResult
    static func activate(_ host: SessionHost, origin: HookOrigin) -> Bool {
        switch host.family {
        case .jetbrains, .vscode:
            // `open -b <ide> <project>`: the IDE focuses the window of an open project.
            // A JetBrains terminal tab cannot be selected from outside the IDE.
            guard let appURL = appURL(host.bundleId) ?? jetBrainsFallback(host) else { return false }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            if !origin.cwd.isEmpty {
                // Open the project the IDE has open, not the subfolder `claude` runs in.
                let markers = host.family == .jetbrains ? [".idea", ".git"] : [".vscode", ".git"]
                let root = ProjectRoot.find(from: origin.cwd, markers: markers)
                // `open` activates the IDE's last window, then the IDE switches to the project:
                // a visible flicker, and a minimized window stays in the Dock. Raise it directly.
                if raiseProjectWindow(appURL: appURL, root: root) { return true }
                NSWorkspace.shared.open([URL(fileURLWithPath: root)], withApplicationAt: appURL,
                                        configuration: configuration, completionHandler: nil)
            } else {
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration, completionHandler: nil)
            }
            return true
        case .terminal, .unknown:
            if host.bundleId == "com.googlecode.iterm2", let id = itermUniqueId(origin.itermSessionId) {
                run(script: """
                tell application "iTerm2"
                    activate
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if unique id of s is "\(id)" then
                                    select w
                                    select t
                                    select s
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell
                """)
                return true
            }
            if host.bundleId == "com.apple.Terminal", !origin.tty.isEmpty {
                run(script: """
                tell application "Terminal"
                    activate
                    repeat with w in windows
                        repeat with t in tabs of w
                            if tty of t is "\(origin.tty)" then
                                set selected of t to true
                                set index of w to 1
                                return
                            end if
                        end repeat
                    end repeat
                end tell
                """)
                return true
            }
            guard let id = host.bundleId else { return false }
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                return running.activate()
            }
            guard let url = appURL(id) else { return false }
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            return true
        }
    }

    private static func appURL(_ bundleId: String?) -> URL? {
        guard let bundleId else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    }

    /// Only TERMINAL_EMULATOR said JetBrains: use the running JetBrains IDE, if exactly one.
    private static func jetBrainsFallback(_ host: SessionHost) -> URL? {
        let running = NSWorkspace.shared.runningApplications.filter {
            ($0.bundleIdentifier ?? "").hasPrefix("com.jetbrains.") || $0.bundleIdentifier == "com.google.android.studio"
        }
        return running.count == 1 ? running[0].bundleURL : nil
    }

    /// Un-minimizes and raises the running IDE's window of `root`, then brings the IDE
    /// forward in one step. Needs Accessibility; false when it can't (caller falls back to `open`).
    private static func raiseProjectWindow(appURL: URL, root: String) -> Bool {
        guard AXIsProcessTrusted() else {
            askForAccessibilityOnce()
            return false
        }
        guard
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == appURL })
        else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement],
              let window = windows.first(where: { isProjectWindow($0, root: root) })
        else { return false }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        // A non-activating panel can't hand activation over (`activate()` may be ignored):
        // ask through Accessibility, which brings only the raised window forward.
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        return true
    }

    /// macOS lists the app under Accessibility only once it has asked: ask on the first
    /// «Открыть» that needs it, never again (the user may have said no on purpose).
    private static func askForAccessibilityOnce() {
        let key = "HostActivator.askedForAccessibility"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        // The value of kAXTrustedCheckOptionPrompt; the global itself is not concurrency-safe.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// JetBrains titles a window "<project> – <file>" (or just "<project>"); its document is
    /// the open file, inside the project.
    private static func isProjectWindow(_ window: AXUIElement, root: String) -> Bool {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &value) == .success,
           let document = value as? String, let path = URL(string: document)?.path,
           path == root || path.hasPrefix(root + "/") {
            return true
        }
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success,
              let title = value as? String
        else { return false }
        let name = (root as NSString).lastPathComponent
        return title == name || title.hasPrefix(name + " – ") || title.hasPrefix(name + " - ")
            || title.hasPrefix(name + " [")
    }

    /// ITERM_SESSION_ID is "w0t1p0:UUID"; AppleScript knows the UUID part.
    private static func itermUniqueId(_ sessionId: String) -> String? {
        let parts = sessionId.split(separator: ":")
        guard parts.count == 2, parts[1].allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return nil }
        return String(parts[1])
    }

    private static func run(script: String) {
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }
}
