import Testing
import Foundation
@testable import MelyCore

@MainActor
@Suite struct PlanUsageTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// As Claude Code 2.1.x sends it to the statusLine command.
    var rateLimits: [String: Any] {
        ["five_hour": ["used_percentage": 42.4, "resets_at": 1_800_000_000 + 2 * 3600 + 14 * 60],
         "seven_day": ["used_percentage": 83, "resets_at": 1_800_000_000 + 3 * 86400 + 4 * 3600]]
    }

    @Test func parsesBothWindows() throws {
        let usage = try #require(PlanUsage(rateLimits: rateLimits, now: t0))
        #expect(usage.fiveHour?.usedPercent == 42.4)
        #expect(usage.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_800_000_000 + 8040))
        #expect(usage.sevenDay?.isWarning == true)
        #expect(usage.fiveHour?.isWarning == false)
        #expect(usage.isWarning)
        #expect(usage.fullest?.usedPercent == 83)
        #expect(PlanUsage.countdown(to: usage.fiveHour!.resetsAt!, from: t0) == "2 ч 14 мин")
        #expect(PlanUsage.countdown(to: usage.sevenDay!.resetsAt!, from: t0) == "3 дн 4 ч")
        #expect(PlanUsage.countdown(to: t0.addingTimeInterval(45 * 60), from: t0) == "45 мин")
        #expect(PlanUsage.shortCountdown(to: usage.fiveHour!.resetsAt!, from: t0) == "2ч 14м")
        #expect(PlanUsage.shortCountdown(to: usage.sevenDay!.resetsAt!, from: t0) == "3д 4ч")
        #expect(PlanUsage.shortCountdown(to: t0.addingTimeInterval(20), from: t0) == "1м")
    }

    @Test func otherTimeFormatsAndMissingData() {
        #expect(PlanWindow.date(1_800_000_000_000) == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(PlanWindow.date("2027-01-15T10:00:00Z") != nil)
        #expect(PlanWindow.date("2027-01-15T10:00:00.123Z") != nil)
        // API key sessions: no plan windows.
        #expect(PlanUsage(rateLimits: [:]) == nil)
        #expect(PlanUsage(rateLimits: ["five_hour": NSNull()]) == nil)
        #expect(PlanUsage(rateLimits: ["five_hour": ["used_percentage": 120]])?.fiveHour?.usedPercent == 120)
    }

    /// What the compact island shows (spec plan-usage, «Лимит в свёрнутой челке»).
    @Test func compactShowsFiveHoursOrWhatRanOut() {
        func usage(_ five: Double?, _ week: Double?) -> PlanUsage {
            PlanUsage(fiveHour: five.map { PlanWindow(usedPercent: $0, resetsAt: t0.addingTimeInterval(80 * 60)) },
                      sevenDay: week.map { PlanWindow(usedPercent: $0, resetsAt: t0.addingTimeInterval(3 * 86400)) },
                      updatedAt: t0)
        }
        // Ordinary use and a week near its limit: the five hours.
        #expect(usage(30, 70).compactWindow?.kind == .fiveHour)
        #expect(usage(20, 85).compactWindow?.window.usedPercent == 20)
        // Five hours used up: that one, with its reset.
        #expect(usage(100, 70).compactWindow?.kind == .fiveHour)
        // The week used up wins over a fresh five hours.
        #expect(usage(10, 100).compactWindow?.kind == .sevenDay)
        // Both used up: the one that frees up later.
        #expect(usage(100, 100).compactWindow?.kind == .sevenDay)
        // Only the week, not used up: nothing in the compact island.
        #expect(usage(nil, 60).compactWindow == nil)
        #expect(usage(nil, 100).compactWindow?.kind == .sevenDay)
    }

    @Test func oldNumbersAreStale() throws {
        let usage = try #require(PlanUsage(rateLimits: rateLimits, now: t0))
        #expect(!usage.isStale(now: t0.addingTimeInterval(15 * 60)))
        #expect(usage.isStale(now: t0.addingTimeInterval(15 * 60 + 1)))
        #expect(usage.ageText(now: t0.addingTimeInterval(2 * 3600 + 5 * 60)) == "обновлено 2 ч 5 мин назад")
    }

    @Test func passedResetStartsOver() throws {
        let usage = try #require(PlanUsage(rateLimits: rateLimits, now: t0))
        let later = usage.current(now: t0.addingTimeInterval(3 * 3600))
        #expect(later.fiveHour?.usedPercent == 0)
        #expect(later.sevenDay?.usedPercent == 83)
    }

    @Test func storeKeepsLastValuesAcrossLaunches() throws {
        let defaults = try #require(UserDefaults(suiteName: "mely-plan-\(UUID().uuidString)"))
        let store = PlanUsageStore(defaults: defaults)
        #expect(store.usage == nil)
        store.update(rateLimits: rateLimits, now: t0)
        store.update(rateLimits: [:], now: t0.addingTimeInterval(60))  // an API key session
        #expect(store.usage?.sevenDay?.usedPercent == 83)
        let relaunched = PlanUsageStore(defaults: defaults)
        #expect(relaunched.usage?.fiveHour?.usedPercent == 42.4)
        #expect(relaunched.usage?.updatedAt == t0)
    }
}

@Suite struct StatusLineInstallTests {
    let relay = "/Users/me/.mely/bin/nc-hook"

    func json(_ data: Data?) -> [String: Any]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    @Test func wrapsTheUsersStatusLine() {
        let mine: [String: Any] = ["type": "command", "command": "~/bin/my-line.sh", "padding": 1]
        let (settings, previous) = ClaudeHookInstaller.installingStatusLine(
            into: ["statusLine": mine], relayPath: relay)
        let line = settings["statusLine"] as? [String: Any]
        #expect(line?["command"] as? String == "\"\(relay)\" --statusline")
        #expect(line?["padding"] as? Int == 1)
        guard case .save(let data) = previous else { Issue.record("not saved"); return }
        #expect(json(data)?["command"] as? String == "~/bin/my-line.sh")
        #expect(ClaudeHookInstaller.statusLineInstalled(in: settings, relayPath: relay))

        // Installing again keeps the saved command instead of wrapping our own wrapper.
        let again = ClaudeHookInstaller.installingStatusLine(into: settings, relayPath: relay)
        #expect(again.previous == .keep)

        let restored = ClaudeHookInstaller.uninstallingStatusLine(from: settings, relayPath: relay, previous: json(data))
        #expect((restored["statusLine"] as? [String: Any])?["command"] as? String == "~/bin/my-line.sh")
    }

    @Test func noStatusLineBeforeMeansNoneAfter() {
        let (settings, previous) = ClaudeHookInstaller.installingStatusLine(
            into: ["model": "opus"], relayPath: relay)
        #expect(previous == .save(nil))
        let restored = ClaudeHookInstaller.uninstallingStatusLine(from: settings, relayPath: relay, previous: nil)
        #expect(restored["statusLine"] == nil)
        #expect(restored["model"] as? String == "opus")
    }

    @Test func setupWritesAndRemovesThePreviousFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mely-sl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = dir.appendingPathComponent("settings.json")
        try Data(#"{"statusLine":{"type":"command","command":"echo hi"}}"#.utf8).write(to: settings)
        let setup = ClaudeCodeSetup(settingsURL: settings, relayURL: dir.appendingPathComponent("bin/nc-hook"))
        #expect(setup.previousStatusLineURL == dir.appendingPathComponent("statusline-previous.json"))

        let install = try setup.prepareInstall()
        #expect(install.diff.contains("--statusline"))
        try setup.apply(install)
        #expect(setup.hooksInstalled())
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: setup.previousStatusLineURL)) as? [String: Any]
        #expect(saved?["command"] as? String == "echo hi")

        try setup.apply(try setup.prepareUninstall())
        let after = try ClaudeSettingsFile.read(at: settings).object
        #expect((after["statusLine"] as? [String: Any])?["command"] as? String == "echo hi")
        #expect(!FileManager.default.fileExists(atPath: setup.previousStatusLineURL.path))
    }

    @Test func hooksWithoutStatusLineNeedAnUpdate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mely-sl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = dir.appendingPathComponent("settings.json")
        let relayURL = dir.appendingPathComponent("bin/nc-hook")
        let hooked = try ClaudeHookInstaller.installing(into: [:], relayPath: relayURL.path)
        try ClaudeHookInstaller.encode(hooked).write(to: settings)
        let setup = ClaudeCodeSetup(settingsURL: settings, relayURL: relayURL)
        #expect(setup.onlyStatusLineMissing())
        #expect(!setup.hooksInstalled())
        let update = try setup.prepareInstall()
        // Only the statusLine is added: the hooks are already there.
        #expect(update.diff.split(separator: "\n").filter { $0.hasPrefix("+ ") }.allSatisfy {
            $0.contains("statusLine") || $0.contains("statusline") || $0.contains("type") || $0.contains("}")
        })
    }
}

@MainActor
@Suite struct PlanUsageAgentsTests {
    func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "PlanUsageAgentsTests-\(UUID().uuidString)"))
    }

    @Test func savedBeforeAgentsIsClaudes() throws {
        let d = try defaults()
        let old = PlanUsage(fiveHour: PlanWindow(usedPercent: 30, resetsAt: nil), sevenDay: nil, updatedAt: Date())
        d.set(try JSONEncoder().encode(old), forKey: "planUsage")
        #expect(PlanUsageStore(agent: .claude, defaults: d).usage?.fiveHour?.usedPercent == 30)
        #expect(PlanUsageStore(agent: .codex, defaults: d).usage == nil)
    }

    @Test func eachAgentKeepsItsOwnNumbersAndAge() throws {
        let d = try defaults()
        let claude = PlanUsageStore(agent: .claude, defaults: d), codex = PlanUsageStore(agent: .codex, defaults: d)
        let old = Date().addingTimeInterval(-2 * 3600)
        claude.update(rateLimits: ["five_hour": ["used_percentage": 10]], now: Date())
        codex.set(PlanUsage(fiveHour: PlanWindow(usedPercent: 90, resetsAt: nil), sevenDay: nil, updatedAt: old, plan: "plus",
                            resetCredits: 2))
        #expect(claude.usage?.isStale() == false)
        #expect(codex.usage?.isStale() == true)
        let again = PlanUsageStore(agent: .codex, defaults: d)
        #expect(again.usage?.fiveHour?.usedPercent == 90)
        #expect(again.usage?.plan == "plus")
        #expect(again.usage?.resetCredits == 2)
        #expect(PlanUsageStore(agent: .claude, defaults: d).usage?.fiveHour?.usedPercent == 10)
    }
}

