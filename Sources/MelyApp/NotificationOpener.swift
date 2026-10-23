import AppKit
import OSLog

private let log = Logger(subsystem: "dev.mely.app", category: "notifications")

/// Opens the app behind a mirrored notification, in front. Not the exact chat: that would
/// mean opening Notification Center and pressing the notification there, and the list
/// sliding out reads as "the notifications opened" instead of the app.
@MainActor
enum NotificationOpener {
    static func open(bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            log.info("open: the app is not installed any more")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }
}
