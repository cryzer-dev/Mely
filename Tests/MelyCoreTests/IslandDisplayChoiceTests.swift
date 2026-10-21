// Portions © 2026 Louis Raillé, MIT License — see THIRD_PARTY_NOTICES.md.
import Testing
@testable import MelyCore

@Suite struct IslandDisplayChoiceTests {
    @Test func storageRoundTrip() {
        for choice: IslandDisplayChoice in [.notch, .menuBar, .followMouse, .display(uuid: "ABC-123")] {
            #expect(IslandDisplayChoice(storageValue: choice.storageValue) == choice)
        }
        #expect(IslandDisplayChoice(storageValue: "") == .notch)
        #expect(IslandDisplayChoice(storageValue: "garbage") == .notch)
        #expect(IslandDisplayChoice(storageValue: "display:") == .notch)
    }

    @Test func resolvesAmongScreens() {
        let screens = [
            IslandDisplayCandidate(uuid: "EXT-1", hasNotch: false, containsMouse: false),
            IslandDisplayCandidate(uuid: "MBP",   hasNotch: true,  containsMouse: false),
            IslandDisplayCandidate(uuid: "EXT-2", hasNotch: false, containsMouse: true),
        ]
        #expect(IslandDisplayResolver.index(for: .notch, in: screens) == 1)
        #expect(IslandDisplayResolver.index(for: .menuBar, in: screens) == 0)
        #expect(IslandDisplayResolver.index(for: .followMouse, in: screens) == 2)
        #expect(IslandDisplayResolver.index(for: .display(uuid: "EXT-2"), in: screens) == 2)
        #expect(IslandDisplayResolver.index(for: .display(uuid: "GONE"), in: screens) == 1)
    }

    @Test func noNotchAnywhereUsesMainScreen() {
        let desk = [
            IslandDisplayCandidate(uuid: "EXT-1", hasNotch: false, containsMouse: false),
            IslandDisplayCandidate(uuid: "EXT-2", hasNotch: false, containsMouse: false),
        ]
        #expect(IslandDisplayResolver.index(for: .notch, in: desk) == nil)
        #expect(IslandDisplayResolver.index(for: .display(uuid: "GONE"), in: desk) == nil)
        #expect(IslandDisplayResolver.index(for: .followMouse, in: desk) == nil)
        #expect(IslandDisplayResolver.index(for: .menuBar, in: []) == nil)
    }
}
