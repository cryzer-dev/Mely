import Testing
@testable import MelyCore

@Test func dataPathsHaveNoSpaces() {
    #expect(!AppInfo.shelfDirectory.path.contains(" "))
    #expect(!AppInfo.socketURL.path.contains(" "))
}
