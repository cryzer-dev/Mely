import Foundation
import Observation

/// Owns the integrations, persists which ones are on, and starts or stops them.
@MainActor
@Observable
public final class IntegrationRegistry {
    public private(set) var integrations: [any Integration] = []
    /// Integrations on at first launch. Everything else starts off.
    public let enabledByDefault: Set<String>

    public var showExperimental: Bool {
        didSet { defaults.set(showExperimental, forKey: Self.experimentalKey) }
    }

    /// Ids switched on, persisted on every change.
    public private(set) var enabledIds: Set<String> {
        didSet { defaults.set(enabledIds.sorted(), forKey: Self.enabledKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored public var permissions: PermissionChecking? {
        didSet { watchPermissions() }
    }
    private static let enabledKey = "enabledIntegrations"
    /// Ids this Mac has seen: a newly added integration gets its default once, a choice
    /// the user made is never overridden.
    private static let seenKey = "seenIntegrations"
    private static let experimentalKey = "showExperimentalIntegrations"

    public init(defaults: UserDefaults = .standard, enabledByDefault: Set<String> = ["claude-code"]) {
        self.defaults = defaults
        self.enabledByDefault = enabledByDefault
        self.showExperimental = defaults.bool(forKey: Self.experimentalKey)
        self.enabledIds = (defaults.array(forKey: Self.enabledKey) as? [String]).map(Set.init) ?? enabledByDefault
    }

    public func register(_ integration: any Integration) {
        precondition(!integrations.contains { $0.id == integration.id }, "duplicate integration id \(integration.id)")
        integrations.append(integration)
        var seen = Set(defaults.array(forKey: Self.seenKey) as? [String] ?? [])
        if !seen.contains(integration.id) {
            // Upgrading from a version without it: switch it on if it is on by default.
            // (On a first launch enabledIds already holds the defaults.)
            if enabledByDefault.contains(integration.id) { enabledIds.insert(integration.id) }
            seen.insert(integration.id)
            defaults.set(seen.sorted(), forKey: Self.seenKey)
        }
        watchPermissions()
    }

    /// Integrations shown in Settings: experimental ones only on request.
    public var visible: [any Integration] {
        integrations.filter { showExperimental || !$0.isExperimental }
    }

    public func isEnabled(_ id: String) -> Bool {
        enabledIds.contains(id)
    }

    /// Persists the switch and starts or stops the integration. Switching on asks for the
    /// first missing permission (a prompt where macOS has one, System Settings otherwise).
    public func setEnabled(_ id: String, _ on: Bool) async {
        if on { enabledIds.insert(id) } else { enabledIds.remove(id) }
        watchPermissions()
        guard let integration = integrations.first(where: { $0.id == id }) else { return }
        if on {
            if let permissions, let missing = integration.requiredPermissions.first(where: { !permissions.isGranted($0) }) {
                await permissions.request(missing)
            }
            await integration.start()
        } else {
            await integration.stop()
        }
    }

    /// What Settings shows: off when switched off, "needs access" while a required
    /// permission is missing (re-checked live), else what the integration reports.
    public func status(of integration: any Integration) -> IntegrationStatus {
        guard isEnabled(integration.id) else { return .off }
        guard let permissions else { return integration.status }
        _ = permissions.revision
        return .resolve(required: integration.requiredPermissions,
                        isGranted: permissions.isGranted,
                        otherwise: integration.status)
    }

    private func watchPermissions() {
        let needed = integrations.filter { isEnabled($0.id) }.flatMap(\.requiredPermissions)
        permissions?.watch(Set(needed))
    }

    /// Starts every enabled integration (app launch).
    public func startEnabled() async {
        for integration in integrations where isEnabled(integration.id) {
            await integration.start()
        }
    }
}
