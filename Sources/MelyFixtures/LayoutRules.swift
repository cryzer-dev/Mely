import CoreGraphics
import MelyUI

/// What the layout checks hold every variant to (openspec island-layout): nothing leaves
/// its container, nothing in a row overlaps, nothing on screen is empty, no text is cut.
/// Each rule returns what broke it, one line per problem.
public enum LayoutRules {
    /// Rounding in layout: half a point either way is not a bug.
    static let tolerance: CGFloat = 0.5

    public static func check(_ probes: [LayoutProbe]) -> [String] {
        inside(probes) + rows(probes) + nonEmpty(probes) + contains(probes) + text(probes)
    }

    /// Each probe within its `inside` probe, which must be there; in a scrolling container
    /// only across, as rows scroll out of sight up and down.
    public static func inside(_ probes: [LayoutProbe]) -> [String] {
        let byId = index(probes)
        return probes.compactMap { probe in
            guard let id = probe.inside else { return nil }
            guard let parent = byId[id] else { return "\(probe.id): нет контейнера \(id) среди меток" }
            let outer = parent.frame.insetBy(dx: -tolerance, dy: -tolerance)
            let f = probe.frame
            let across = f.minX >= outer.minX && f.maxX <= outer.maxX
            let down = parent.scrolls || (f.minY >= outer.minY && f.maxY <= outer.maxY)
            return across && down ? nil : "\(probe.id) выходит за \(id): \(describe(f)) вне \(describe(parent.frame))"
        }
    }

    /// Probes of one row do not overlap.
    public static func rows(_ probes: [LayoutProbe]) -> [String] {
        var problems: [String] = []
        let rows = Dictionary(grouping: probes.filter { $0.row != nil }, by: { $0.row! })
        for (row, members) in rows.sorted(by: { $0.key < $1.key }) {
            for (i, a) in members.enumerated() {
                for b in members.dropFirst(i + 1) {
                    let overlap = a.frame.intersection(b.frame)
                    if !overlap.isNull, overlap.width > tolerance, overlap.height > tolerance {
                        problems.append("\(a.id) и \(b.id) наезжают друг на друга в ряду \(row)")
                    }
                }
            }
        }
        return problems
    }

    /// Nothing on screen flat: a width without height or the other way round. A slot with
    /// nothing in it at all (zero by zero) draws nothing and is fine.
    public static func nonEmpty(_ probes: [LayoutProbe]) -> [String] {
        probes.compactMap { probe in
            (probe.frame.width > tolerance) == (probe.frame.height > tolerance) ? nil : "\(probe.id) пустой: \(describe(probe.frame))"
        }
    }

    /// A probe that must hold another one does: a capsule with nothing inside is a bug.
    public static func contains(_ probes: [LayoutProbe]) -> [String] {
        probes.compactMap { probe in
            guard let id = probe.contains else { return nil }
            let outer = probe.frame.insetBy(dx: -tolerance, dy: -tolerance)
            let held = probes.contains { $0.id == id && $0.frame.width > tolerance && $0.frame.height > tolerance
                && outer.contains($0.frame) }
            return held ? nil : "\(probe.id) без содержимого (\(id))"
        }
    }

    /// Text gets the height it needs at its width.
    public static func text(_ probes: [LayoutProbe]) -> [String] {
        probes.compactMap { probe in
            guard let ideal = probe.idealHeight, ideal > probe.frame.height + 1 else { return nil }
            return "\(probe.id) обрезан по высоте: нужно \(Int(ideal.rounded())), есть \(Int(probe.frame.height.rounded()))"
        }
    }

    // MARK: The chat

    /// The chat at rest: scrolled to its end, the last message whole above the field; at the
    /// top, the first message whole and not faded.
    public static func chat(_ probes: [LayoutProbe]) -> [String] {
        let byId = index(probes)
        guard let viewport = byId["chat.viewport"]?.frame else { return [] }
        let messages = probes.filter { $0.id.hasPrefix("chat.message.") }
            .sorted { $0.frame.minY < $1.frame.minY }
        guard let first = messages.first, let last = messages.last else { return [] }
        var problems: [String] = []
        if last.frame.maxY > viewport.maxY + tolerance {
            problems.append("\(last.id) обрезан снизу: \(Int((last.frame.maxY - viewport.maxY).rounded())) pt под краем")
        }
        // Nothing above it: the first message is at the top and must be fully seen.
        if first.frame.minY >= viewport.minY - tolerance, byId["chat.fade"] != nil {
            problems.append("\(first.id) под затемнением, хотя выше ничего нет")
        }
        if first.frame.minY < viewport.minY - tolerance, last.frame.maxY <= viewport.maxY + tolerance,
           messages.reduce(0, { $0 + $1.frame.height }) < viewport.height {
            problems.append("\(first.id) обрезан сверху, хотя переписка помещается")
        }
        return problems
    }

    static func index(_ probes: [LayoutProbe]) -> [String: LayoutProbe] {
        Dictionary(probes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    static func describe(_ r: CGRect) -> String {
        "(\(Int(r.minX.rounded())),\(Int(r.minY.rounded())) \(Int(r.width.rounded()))×\(Int(r.height.rounded())))"
    }
}
