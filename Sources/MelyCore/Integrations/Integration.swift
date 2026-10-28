import Foundation

/// A system privacy permission an integration needs. Asked for only when it is enabled.
public enum SystemPermission: Hashable, Sendable {
    case fullDiskAccess
    case calendars
    case reminders
    case microphone
    case speechRecognition
    case automation(bundleId: String)
    case accessibility
    case desktopFolder

    public var title: String {
        switch self {
        case .fullDiskAccess: "Доступ к диску"
        case .calendars: "Календари"
        case .reminders: "Напоминания"
        case .microphone: "Микрофон"
        case .speechRecognition: "Распознавание речи"
        case .automation: "Автоматизация"
        case .accessibility: "Универсальный доступ"
        case .desktopFolder: "Папка «Рабочий стол»"
        }
    }
}

public enum IntegrationStatus: Equatable, Sendable {
    case off
    case running
    /// On, but waiting for a one-time setup the user confirms (e.g. Claude Code hooks).
    case needsSetup(String)
    case needsPermission(SystemPermission)
    case error(String)
}

/// Something that can be switched on and off in Settings. A switched-off integration
/// holds nothing in memory, polls nothing and asks for no permission.
@MainActor
public protocol Integration: AnyObject {
    /// Stable id: the key in UserDefaults and Keychain. Never rename it.
    var id: String { get }
    var displayName: String { get }
    var summary: String { get }
    /// Experimental modules are listed only with "Show experimental integrations" on.
    var isExperimental: Bool { get }
    var status: IntegrationStatus { get }
    var requiredPermissions: [SystemPermission] { get }
    func start() async
    func stop() async
    /// Extra actions shown under an enabled integration in Settings ("Отключить hooks").
    var actions: [IntegrationAction] { get }
}

public extension Integration {
    var isExperimental: Bool { false }
    var requiredPermissions: [SystemPermission] { [] }
    var actions: [IntegrationAction] { [] }
}

/// A button in an integration's Settings row.
public struct IntegrationAction: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let isDestructive: Bool
    public let perform: @MainActor @Sendable () -> Void

    public init(id: String, title: String, isDestructive: Bool = false, perform: @escaping @MainActor @Sendable () -> Void) {
        self.id = id
        self.title = title
        self.isDestructive = isDestructive
        self.perform = perform
    }
}
