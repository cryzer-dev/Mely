import Testing
@testable import MelyCore

@Suite struct PermissionStatusTests {
    @Test func missingPermissionWins() {
        let status = IntegrationStatus.resolve(required: [.calendars, .fullDiskAccess],
                                               isGranted: { $0 == .calendars },
                                               otherwise: .running)
        #expect(status == .needsPermission(.fullDiskAccess))
    }

    @Test func allGrantedKeepsOwnStatus() {
        #expect(IntegrationStatus.resolve(required: [.calendars], isGranted: { _ in true }, otherwise: .running) == .running)
        #expect(IntegrationStatus.resolve(required: [], isGranted: { _ in false }, otherwise: .error("x")) == .error("x"))
    }

    @Test func remindersIsItsOwnPermission() {
        #expect(SystemPermission.reminders.title == "Напоминания")
        #expect(IntegrationStatus.resolve(required: [.reminders], isGranted: { $0 == .calendars },
                                          otherwise: .running) == .needsPermission(.reminders))
    }
}
