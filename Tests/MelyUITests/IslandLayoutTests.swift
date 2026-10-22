import Testing
import MelyUI
import MelyFixtures

/// Every variant of the island, laid out offscreen and held to `LayoutRules`
/// (openspec island-layout).
@MainActor
@Suite struct IslandLayoutTests {
    /// Bugs the checks found that are not fixed yet, by a part of the failure text. Each one
    /// goes with its fix: a known issue that stops happening fails the test.
    static let knownIssues: [(match: String, why: String)] = [
        ("header.usage без содержимого", "Пустая капсула лимитов в шапке без данных о 5-часовом окне"),
    ]

    @Test func everyVariantHolds() async {
        var failures: [String] = []
        for variant in LayoutMatrix.all {
            let probes = await LayoutHarness.lay(variant).probes
            if probes.isEmpty { failures.append("\(variant.name): нет ни одной метки вёрстки"); continue }
            failures += (LayoutRules.check(probes) + LayoutRules.chat(probes)).map { "\(variant.name): \($0)" }
        }
        for known in Self.knownIssues {
            let matching = failures.filter { $0.contains(known.match) }
            failures.removeAll { $0.contains(known.match) }
            withKnownIssue(Comment(rawValue: known.why)) {
                if !matching.isEmpty { Issue.record(Comment(rawValue: matching.joined(separator: "\n"))) }
            }
        }
        if !failures.isEmpty {
            Issue.record(Comment(rawValue: "\(failures.count) нарушений:\n" + failures.joined(separator: "\n")))
        }
    }
}
