import AppKit
import SwiftUI
import Observation
import OSLog
import MelyCore
import MelyUI

private let log = Logger(subsystem: "dev.mely.app", category: "notifications")

/// Mirrors the notifications of chosen apps (Telegram, Claude, browsers…) into the notch,
/// read from the Notification Center database. Needs Full Disk Access.
@MainActor
@Observable
final class NotificationMirrorIntegration: Integration {
    let id = "notifications"
    let displayName = "Уведомления"
    let summary = "Сообщения Telegram и Телемоста, ответы Claude и уведомления сайтов в челке"
    let requiredPermissions: [SystemPermission] = [.fullDiskAccess]
    private(set) var status: IntegrationStatus = .off
    /// Exists while on: the overview's "Сообщения" tab.
    private(set) var messages: MirroredMessages?

    @ObservationIgnored let settings = NotificationMirrorSettings(installed: {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
    })
    @ObservationIgnored private var watcher: NotificationWatcher?
    @ObservationIgnored private var retry: Timer?
    @ObservationIgnored private var settingsWindow: NSWindow?
    /// Drops read or dismissed notifications from the list.
    @ObservationIgnored private var pruneTimer: Timer?
    /// Shows a preview under the notch.
    @ObservationIgnored var peek: ((PeekContent) -> Void)?

    var actions: [IntegrationAction] {
        guard status != .off else { return [] }
        return [IntegrationAction(id: "apps", title: "Приложения…") { [weak self] in self?.showSettings() }]
    }

    func start() async {
        messages = messages ?? MirroredMessages()
        startWatching()
    }

    func stop() async {
        retry?.invalidate(); retry = nil
        pruneTimer?.invalidate(); pruneTimer = nil
        watcher?.stop(); watcher = nil
        messages = nil
        status = .off
    }

    private func startWatching() {
        let watcher = NotificationWatcher { [weak self] result in
            Task { @MainActor in self?.receive(result) }
        }
        do {
            try watcher.start()
            self.watcher = watcher
            retry?.invalidate(); retry = nil
            status = .running
            log.info("mirror started")
            startPruning()
        } catch let failure as NotificationDatabase.Failure {
            fail(failure)
        } catch {
            fail(.incompatible(error.localizedDescription))
        }
    }

    /// Every 3 s: what Notification Center no longer has (read in the app, dismissed)
    /// leaves the list too.
    private func startPruning() {
        guard pruneTimer == nil else { return }
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let messages = self.messages, !messages.items.isEmpty,
                      let database = self.watcher?.database else { return }
                let ids = messages.items.map(\.id)
                Task.detached {
                    guard let alive = try? database.existing(ids) else { return }
                    await MainActor.run { messages.keep(only: alive) }
                }
            }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        pruneTimer = t
    }

    /// Opens the chat behind a notification (list row or preview) and drops it: read.
    func open(id: Int64) {
        guard let item = messages?.items.first(where: { $0.id == id }) else { return }
        messages?.remove(id)
        NotificationOpener.open(uuid: item.uuid, bundleId: item.bundleId)
    }

    /// The preview under the notch was clicked: its id is "notification-<rec_id>".
    func openPreview(_ peekId: String) -> Bool {
        guard peekId.hasPrefix("notification-"), let id = Int64(peekId.dropFirst("notification-".count)) else { return false }
        open(id: id)
        return true
    }

    /// No access yet: try again every few seconds, so granting Full Disk Access is enough.
    private func fail(_ failure: NotificationDatabase.Failure) {
        watcher?.stop(); watcher = nil
        switch failure {
        case .noAccess:
            status = .needsPermission(.fullDiskAccess)
            guard retry == nil else { return }
            let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.watcher == nil, self.messages != nil else { return }
                    self.startWatching()
                }
            }
            RunLoop.main.add(t, forMode: .common)
            retry = t
        case .incompatible(let reason):
            status = .error("Несовместимая версия macOS: не удаётся прочитать уведомления")
            log.error("mirror incompatible: \(reason, privacy: .public)")
        }
    }

    private func receive(_ result: Result<[MirroredNotification], NotificationDatabase.Failure>) {
        switch result {
        case .failure(let failure):
            fail(failure)
        case .success(let list):
            let focusOn = settings.quietInFocus && SystemFocus.isOn()
            for n in list {
                let name = Self.appName(n.bundleId)
                let decision = MirrorDecision.decide(n, apps: settings.apps, hideText: settings.hideText,
                                                     quietInFocus: settings.quietInFocus, focusOn: focusOn, appName: name)
                // App and outcome only: never the text.
                log.info("notification from \(n.bundleId, privacy: .public): \(String(describing: decision).prefix(8), privacy: .public)")
                switch decision {
                case .ignore:
                    continue
                case .collect:
                    let preview = MirrorDecision.decide(n, apps: settings.apps, hideText: settings.hideText,
                                                        quietInFocus: false, focusOn: false, appName: name)
                    if case .preview(let title, let text) = preview { messages?.add(n, appName: name, title: title, text: text) }
                case .preview(let title, let text):
                    messages?.add(n, appName: name, title: title, text: text)
                    peek?(PeekContent(id: "notification-\(n.id)", symbol: "bell.fill", tint: .blue,
                                      title: title, subtitle: text, appBundleId: n.bundleId, opensApp: true))
                }
            }
        }
    }

    static func appName(_ bundleId: String) -> String {
        if let known = NotificationMirrorSettings.suggested.first(where: {
            $0.id.caseInsensitiveCompare(bundleId) == .orderedSame
        }) { return known.name }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return bundleId }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    func showSettings() {
        settingsWindow?.close()
        // Suggested apps that are installed, plus every app already in the database.
        var ids = NotificationMirrorSettings.suggested.map(\.id).filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
        func listed(_ id: String) -> Bool { ids.contains { $0.caseInsensitiveCompare(id) == .orderedSame } }
        for id in (try? watcher?.database.knownApps()) ?? [] where !listed(id) && !id.hasPrefix("_")
            && NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil {
            ids.append(id)
        }
        for id in settings.apps where !listed(id) { ids.append(id) }
        let candidates = ids.map { NotificationMirrorSettingsView.Candidate(id: $0, name: Self.appName($0)) }
        let view = NotificationMirrorSettingsView(
            settings: settings, candidates: candidates,
            openSystemNotifications: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            },
            close: { [weak self] in
                self?.settingsWindow?.close()
                self?.settingsWindow = nil
            })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Mely — уведомления"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
