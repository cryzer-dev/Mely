import Foundation

/// Reads and asks for macOS privacy permissions. The app provides the real
/// implementation (TCC, EventKit, AVFoundation…); tests use a fake.
@MainActor
public protocol PermissionChecking: AnyObject {
    /// Bumps when a re-check finds a change; reading it subscribes a view to grant changes.
    var revision: Int { get }
    func isGranted(_ permission: SystemPermission) -> Bool
    /// Re-check these permissions periodically (grants change in System Settings without notice).
    func watch(_ permissions: Set<SystemPermission>)
    /// Shows the system prompt when macOS has one; otherwise opens System Settings.
    func request(_ permission: SystemPermission) async
}

public extension IntegrationStatus {
    /// Status of an enabled integration: the first missing permission wins over whatever
    /// the integration reports, so a revoked grant shows up as "needs access".
    static func resolve(required: [SystemPermission],
                        isGranted: (SystemPermission) -> Bool,
                        otherwise status: IntegrationStatus) -> IntegrationStatus {
        if let missing = required.first(where: { !isGranted($0) }) { return .needsPermission(missing) }
        return status
    }
}
