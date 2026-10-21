import AppKit
import SwiftUI
import MelyCore
import MelyUI
import ServiceManagement

/// The Settings window, opened from the menu bar item: sections in a sidebar.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let registry: IntegrationRegistry
    private let characters: CharacterSettings
    private let behavior: IslandBehavior
    private let updates: UpdateState
    private let displayChanged: () -> Void
    /// The island: folded before the window shows, and the window kept below it (its screen
    /// and the lowest edge the window's top may reach).
    var foldIsland: () -> Void = {}
    var islandArea: () -> (screen: NSScreen, bottom: CGFloat)? = { nil }

    init(registry: IntegrationRegistry, characters: CharacterSettings, behavior: IslandBehavior, updates: UpdateState,
         displayChanged: @escaping () -> Void) {
        self.registry = registry
        self.characters = characters
        self.behavior = behavior
        self.updates = updates
        self.displayChanged = displayChanged
    }

    func show(_ section: SettingsSection? = nil) {
        if let section { UserDefaults.standard.set(section.rawValue, forKey: SettingsSection.defaultsKey) }
        if window == nil {
            let view = SettingsRoot(registry: registry, characters: characters, behavior: behavior,
                                    updates: updates, displayChanged: displayChanged)
                .frame(minWidth: 720, minHeight: 560)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Настройки \(AppInfo.name)"
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 780, height: 620))
            window.center()
            self.window = window
        }
        foldIsland()
        NSApp.activate()
        if let window { keepBelowIsland(window) }
        window?.makeKeyAndOrderFront(nil)
    }

    /// A window under the island (opened there, or dragged up earlier) moves down below it.
    private func keepBelowIsland(_ window: NSWindow) {
        guard let (screen, bottom) = islandArea(),
              screen.frame.intersects(window.frame) || window.screen == nil else { return }
        let top = min(bottom, screen.visibleFrame.maxY) - 8
        var frame = window.frame
        guard frame.maxY > top else { return }
        frame.origin.y = max(screen.visibleFrame.minY, top - frame.height)
        window.setFrame(frame, display: false)
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, character, integrations, shortcuts
    static let defaultsKey = "settingsSection"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Основные"
        case .character: "Персонаж"
        case .integrations: "Интеграции"
        case .shortcuts: "Клавиши"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .character: "face.smiling.inverse"
        case .integrations: "puzzlepiece.extension.fill"
        case .shortcuts: "keyboard.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: Color(white: 0.55)
        case .character: Color(red: 1.0, green: 0.62, blue: 0.68)
        case .integrations: Color(red: 0.49, green: 0.36, blue: 1.0)
        case .shortcuts: Color(red: 0.39, green: 0.4, blue: 0.95)
        }
    }
}

/// Sidebar with coloured icons on the left, the section on the right.
private struct SettingsRoot: View {
    let registry: IntegrationRegistry
    let characters: CharacterSettings
    let behavior: IslandBehavior
    let updates: UpdateState
    let displayChanged: () -> Void
    @AppStorage(SettingsSection.defaultsKey) private var selected: SettingsSection = .general
    @State private var launchAtLogin = LoginItem.isOn

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AppInfo.name).font(.system(size: 13, weight: .semibold))
                        Text(AppInfo.version).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
                List(SettingsSection.allCases, selection: Binding(get: { Optional(selected) },
                                                                  set: { if let v = $0 { selected = v } })) { section in
                    Label {
                        Text(section.title)
                    } icon: {
                        Image(systemName: section.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(section.color, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .tag(section)
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 220)
        } detail: {
            detail
                .navigationTitle(selected.title)
        }
    }

    @ViewBuilder private var detail: some View {
        switch selected {
        case .general:
            GeneralSettingsView(
                behavior: behavior,
                sounds: .init(test: { SoundEngine.shared.play(.finish, force: true) },
                              openFolder: { SoundEngine.shared.revealCustomFolder() },
                              reload: { SoundEngine.shared.reload(); return SoundEngine.shared.customized },
                              customized: SoundEngine.shared.customized),
                launchAtLogin: Binding(get: { launchAtLogin }, set: { launchAtLogin = LoginItem.set($0) }),
                updates: updates,
                displayChanged: displayChanged)
        case .character:
            CharacterSettingsView(settings: characters)
        case .integrations:
            IntegrationsSettingsView(registry: registry, openPermission: { permission in
                Task { await registry.permissions?.request(permission) }
            })
        case .shortcuts:
            ShortcutsSettingsView()
        }
    }
}

/// «Запускать при входе в систему» through SMAppService (macOS 13+).
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns what actually happened: registration can fail (an unsigned build).
    static func set(_ on: Bool) -> Bool {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("login item: \(error.localizedDescription)")
        }
        return isOn
    }
}

/// Deep links into System Settings → Privacy & Security.
enum SystemSettingsLinks {
    static func url(for permission: SystemPermission) -> URL? {
        let base = "x-apple.systempreferences:com.apple.preference.security?"
        let anchor: String = switch permission {
        case .fullDiskAccess: "Privacy_AllFiles"
        case .calendars: "Privacy_Calendars"
        case .microphone: "Privacy_Microphone"
        case .speechRecognition: "Privacy_SpeechRecognition"
        case .automation: "Privacy_Automation"
        case .accessibility: "Privacy_Accessibility"
        case .desktopFolder: "Privacy_FilesAndFolders"
        }
        return URL(string: base + anchor)
    }

    @MainActor static func open(_ permission: SystemPermission) {
        if let url = url(for: permission) { NSWorkspace.shared.open(url) }
    }
}
