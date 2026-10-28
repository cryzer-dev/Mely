import AppKit
import AVFoundation
import ApplicationServices
import EventKit
import Speech
import Observation
import MelyCore

/// Real permission checks. `revision` bumps whenever a re-check finds a change, so
/// views and integrations that read it refresh without a restart.
@MainActor
@Observable
final class SystemPermissions: PermissionChecking {
    var revision = 0
    @ObservationIgnored private var lastSnapshot: [SystemPermission: Bool] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var watched: Set<SystemPermission> = []

    /// Permissions to re-check every few seconds (those of enabled integrations).
    func watch(_ permissions: Set<SystemPermission>) {
        watched = permissions
        recheck()
        timer?.invalidate()
        guard !permissions.isEmpty else { return }
        // Grants change in System Settings, which sends no notification: poll gently.
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheck() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func recheck() {
        var snapshot: [SystemPermission: Bool] = [:]
        for permission in watched { snapshot[permission] = isGranted(permission) }
        if snapshot != lastSnapshot {
            lastSnapshot = snapshot
            revision += 1
        }
    }

    func isGranted(_ permission: SystemPermission) -> Bool {
        switch permission {
        case .fullDiskAccess:
            // The Notification Center database is TCC-protected: readable only with Full Disk Access.
            let db = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
            guard let handle = try? FileHandle(forReadingFrom: db) else { return false }
            try? handle.close()
            return true
        case .calendars:
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        case .reminders:
            return EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .speechRecognition:
            return SFSpeechRecognizer.authorizationStatus() == .authorized
        case .automation(let bundleId):
            return automationStatus(bundleId, ask: false) == noErr
        case .accessibility:
            return AXIsProcessTrusted()
        case .desktopFolder:
            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            return (try? FileManager.default.contentsOfDirectory(atPath: desktop.path)) != nil
        }
    }

    func request(_ permission: SystemPermission) async {
        switch permission {
        case .calendars:
            _ = try? await EKEventStore().requestFullAccessToEvents()
            // macOS asks only once: an app with "add events only" (or a "no") gets no new
            // prompt, the switch is in System Settings, where Mely is already listed.
            if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
                SystemSettingsLinks.open(.calendars)
            }
        case .reminders:
            _ = try? await EKEventStore().requestFullAccessToReminders()
            // Same as calendars: after a "no" macOS never asks again.
            if EKEventStore.authorizationStatus(for: .reminder) != .fullAccess {
                SystemSettingsLinks.open(.reminders)
            }
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .speechRecognition:
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { _ in done.resume() }
            }
        case .automation(let bundleId):
            // Blocks until the user answers the prompt: run it off the main thread.
            _ = await Task.detached { Self.automationStatusDetached(bundleId, ask: true) }.value
        case .accessibility:
            // The value of kAXTrustedCheckOptionPrompt; the global itself is not concurrency-safe.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .desktopFolder:
            // Touching the folder makes macOS show its prompt.
            _ = isGranted(.desktopFolder)
        case .fullDiskAccess:
            // No prompt exists for Full Disk Access: the user adds the app in System Settings.
            SystemSettingsLinks.open(.fullDiskAccess)
        }
        recheck()
    }

    private func automationStatus(_ bundleId: String, ask: Bool) -> OSStatus {
        Self.automationStatusDetached(bundleId, ask: ask)
    }

    nonisolated private static func automationStatusDetached(_ bundleId: String, ask: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let status = bundleId.withCString { ptr in
            AECreateDesc(DescType(typeApplicationBundleID), ptr, strlen(ptr), &target)
        }
        guard status == noErr else { return OSStatus(status) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard),
                                                     AEEventID(typeWildCard), ask)
    }
}
