import Testing
import Foundation
@testable import MelyCore

@Suite struct WardrobeTests {
    let calendar = Calendar(identifier: .gregorian)

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func seasons() {
        #expect(Wardrobe.season(on: date(2026, 10, 24), calendar: calendar) == nil)
        #expect(Wardrobe.season(on: date(2026, 10, 25), calendar: calendar) == .halloween)
        #expect(Wardrobe.season(on: date(2026, 10, 31), calendar: calendar) == .halloween)
        #expect(Wardrobe.season(on: date(2026, 11, 1), calendar: calendar) == .halloween)
        #expect(Wardrobe.season(on: date(2026, 11, 2), calendar: calendar) == nil)
        #expect(Wardrobe.season(on: date(2026, 12, 19), calendar: calendar) == nil)
        #expect(Wardrobe.season(on: date(2026, 12, 20), calendar: calendar) == .newYear)
        #expect(Wardrobe.season(on: date(2027, 1, 1), calendar: calendar) == .newYear)
        #expect(Wardrobe.season(on: date(2027, 1, 10), calendar: calendar) == .newYear)
        #expect(Wardrobe.season(on: date(2027, 1, 11), calendar: calendar) == nil)
        #expect(Wardrobe.season(on: date(2026, 6, 1), calendar: calendar) == nil)
    }

    @Test func seasonDressesUnlessTheUserChoseDuringIt() {
        let own = Outfit(items: [.head: .beanie], chosenAt: date(2026, 9, 1))
        // In season, an older choice gives way; after it, the own outfit comes back.
        #expect(Wardrobe.worn(own, seasonal: true, now: date(2026, 10, 31), calendar: calendar) == OutfitSet.halloween.outfit)
        #expect(Wardrobe.worn(own, seasonal: true, now: date(2026, 11, 3), calendar: calendar) == [.head: .beanie])
        // Switched off: never.
        #expect(Wardrobe.worn(own, seasonal: false, now: date(2026, 10, 31), calendar: calendar) == [.head: .beanie])
        // Chosen during the season (marked manual): it stays.
        let manual = Outfit(items: [.eyes: .sunglasses], chosenAt: date(2026, 10, 27))
        #expect(Wardrobe.worn(manual, seasonal: true, now: date(2026, 10, 31), calendar: calendar) == [.eyes: .sunglasses])
        // New year over the year boundary: chosen on Dec 21 still counts on Jan 5.
        let winter = Outfit(items: [.head: .crown], chosenAt: date(2026, 12, 21))
        #expect(Wardrobe.worn(winter, seasonal: true, now: date(2027, 1, 5), calendar: calendar) == [.head: .crown])
        let autumn = Outfit(items: [.head: .crown], chosenAt: date(2026, 11, 20))
        #expect(Wardrobe.worn(autumn, seasonal: true, now: date(2027, 1, 5), calendar: calendar) == OutfitSet.newYear.outfit)
    }

    @Test func setsFillOneThingPerSlot() {
        for set in OutfitSet.allCases {
            #expect(set.outfit.count == set.items.count, "\(set) puts two things in one slot")
        }
        #expect(Accessory.allCases.allSatisfy { Accessory.items(in: $0.slot).contains($0) })
    }
}

@MainActor
@Suite struct CharacterSettingsTests {
    func fresh() -> (CharacterSettings, UserDefaults) {
        let name = "mely-tests-character-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (CharacterSettings(defaults: defaults), defaults)
    }

    @Test func customizationIsKeptPerLookAndResets() {
        let (settings, defaults) = fresh()
        #expect(settings.look.id == "mely")
        settings.set("color", to: .color(BuiltInLooks.nectarine), for: "mely")
        settings.set("tail", to: .bool(false), for: "fox")
        #expect(settings.values(for: BuiltInLooks.mely)["color"] == .color(BuiltInLooks.nectarine))
        #expect(settings.values(for: BuiltInLooks.mely)["leaf"] == .bool(true))
        // Survives a relaunch.
        let again = CharacterSettings(defaults: defaults)
        #expect(again.values(for: BuiltInLooks.fox)["tail"] == .bool(false))
        again.reset("mely")
        #expect(again.values(for: BuiltInLooks.mely)["color"] == .color(BuiltInLooks.cream))
        #expect(again.values(for: BuiltInLooks.mely)["crease"] == .bool(false))
        #expect(again.values(for: BuiltInLooks.fox)["tail"] == .bool(false))
    }

    @Test func outfitsBelongToEachLook() {
        let (settings, _) = fresh()
        settings.dressesBySeason = false
        settings.wear(.wizard, for: "fawn")
        settings.wear(.headphones, in: .head, for: "fox")
        settings.select("fox")
        #expect(settings.appearance().outfit == [.head: .headphones])
        settings.select("fawn")
        #expect(settings.appearance().outfit == OutfitSet.wizard.outfit)
        settings.wear(nil, in: .held, for: "fawn")
        #expect(settings.appearance().outfit[.held] == nil)
        #expect(settings.appearance().outfit[.head] == .wizardHat)
    }

    @Test func echoedValuesAreNotChoices() {
        let (settings, defaults) = fresh()
        // A control writing back what it shows changes nothing, so a season still dresses.
        settings.set("cheeks", to: .bool(true), for: "conure")
        settings.wear(nil, in: .head, for: "mely")
        #expect(settings.outfit(for: "mely").chosenAt == nil)
        #expect(defaults.data(forKey: CharacterSettings.defaultsKey) == nil)
    }

    @Test func hiddenLooks() {
        let (settings, _) = fresh()
        settings.setHidden("lamb", true)
        #expect(!settings.visibleLooks().contains { $0.id == "lamb" })
        #expect(settings.visibleLooks(showHidden: true).contains { $0.id == "lamb" })
        // A look that no longer exists (an old pixel pet) falls back to Mely.
        settings.select("pack:cat")
        #expect(settings.look.id == "mely")
        // The minimal look is always last.
        #expect(settings.allLooks.last?.kind == .minimal)
    }
}
