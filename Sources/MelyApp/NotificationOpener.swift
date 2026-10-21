import AppKit
import ApplicationServices
import OSLog

private let log = Logger(subsystem: "dev.mely.app", category: "notifications")

/// Opens a mirrored notification the way clicking its banner would: the exact chat, not
/// just the app (as nonja does). Notification Center opens for a moment, the notification
/// is found by its identifier and pressed. Needs Accessibility; without it, or when the
/// notification is gone, the app simply opens.
@MainActor
enum NotificationOpener {
    private static var queue: Task<Void, Never>?

    static func open(uuid: String?, bundleId: String) {
        let previous = queue
        queue = Task {
            await previous?.value
            log.info("open: uuid=\(uuid != nil, privacy: .public) accessibility=\(AXIsProcessTrusted(), privacy: .public)")
            if let uuid, AXIsProcessTrusted(), await press(uuid: uuid) {
                log.info("opened notification in place")
                return
            }
            log.info("opened the app instead")
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
        }
    }

    private static func press(uuid: String) async -> Bool {
        guard let center = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
        else { return false }
        let app = AXUIElementCreateApplication(center.processIdentifier)
        guard toggleNotificationCenter() else {
            log.info("open: could not open Notification Center")
            return false
        }
        for _ in 0..<40 {
            if let target = find(uuid, in: app) {
                AXUIElementPerformAction(target, kAXPressAction as CFString)
                // Pressing opens the chat and closes the list by itself.
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        log.info("open: notification not found in Notification Center")
        // Not there (already read): close the list again.
        toggleNotificationCenter()
        return false
    }

    /// Clicks the clock in the menu bar, which opens or closes Notification Center.
    @discardableResult
    private static func toggleNotificationCenter() -> Bool {
        guard let control = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first
        else { return false }
        let app = AXUIElementCreateApplication(control.processIdentifier)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success, let bar else { return false }
        var kids: CFTypeRef?
        AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &kids)
        for item in (kids as? [AXUIElement]) ?? [] {
            var id: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &id)
            if (id as? String) == "com.apple.menuextra.clock" {
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
        }
        return false
    }

    private static func find(_ uuid: String, in root: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth <= 12 else { return nil }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(root, kAXIdentifierAttribute as CFString, &value) == .success,
           let id = value as? String, id.caseInsensitiveCompare(uuid) == .orderedSame {
            return root
        }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &kids) == .success,
              let children = kids as? [AXUIElement] else { return nil }
        for child in children {
            if let hit = find(uuid, in: child, depth: depth + 1) { return hit }
        }
        return nil
    }
}
