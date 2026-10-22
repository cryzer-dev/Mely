import SwiftUI

/// Layout checks (MelyUITests): key elements report where they ended up, the tests check
/// that nothing leaves the island, overlaps or is cut. Off in the app: the modifier then
/// leaves the view as it is.
public struct LayoutProbe: Equatable, Sendable {
    /// What the checks hold the element to.
    public struct Rules: Equatable, Sendable {
        /// Elements of one row must not overlap.
        public var row: String?
        /// The element must lie inside the element with this id, when that one is on screen.
        public var inside: String?
        /// The element must hold the element with this id: a capsule with nothing in it is a bug.
        public var contains: String?
        /// A scrolling container: what lies inside it is only held to its width.
        public var scrolls = false
    }

    public let id: String
    /// In the `LayoutProbe.space` coordinates (the checked root).
    public let frame: CGRect
    public let rules: Rules
    /// The height the element needs at its width; larger than `frame` means cut text.
    public let idealHeight: CGFloat?

    public var row: String? { rules.row }
    public var inside: String? { rules.inside }
    public var contains: String? { rules.contains }
    public var scrolls: Bool { rules.scrolls }

    public init(id: String, frame: CGRect, row: String? = nil, inside: String? = nil, contains: String? = nil,
                scrolls: Bool = false, idealHeight: CGFloat? = nil) {
        self.init(id: id, frame: frame, rules: Rules(row: row, inside: inside, contains: contains, scrolls: scrolls),
                  idealHeight: idealHeight)
    }

    init(id: String, frame: CGRect, rules: Rules, idealHeight: CGFloat?) {
        self.id = id
        self.frame = frame
        self.rules = rules
        self.idealHeight = idealHeight
    }

    /// The coordinate space the checked root declares.
    public static let space = "mely.layout"
}

/// Every probe under a view, as a value: a change anywhere below reaches `onPreferenceChange`.
public struct LayoutProbeKey: PreferenceKey {
    public static let defaultValue: [LayoutProbe] = []
    public static func reduce(value: inout [LayoutProbe], nextValue: () -> [LayoutProbe]) {
        value.append(contentsOf: nextValue())
    }
}

/// The ideal height of a probed text, measured in the probe's background.
private struct LayoutIdealKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

private struct LayoutProbesEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Set by the layout checks only.
    var layoutProbesEnabled: Bool {
        get { self[LayoutProbesEnabledKey.self] }
        set { self[LayoutProbesEnabledKey.self] = newValue }
    }
}

private struct LayoutProbeModifier: ViewModifier {
    let id: String
    let rules: LayoutProbe.Rules
    let checksText: Bool
    @Environment(\.layoutProbesEnabled) private var enabled

    func body(content: Content) -> some View {
        if enabled {
            if checksText {
                // A hidden copy at the same width, as tall as it wants to be.
                content
                    .background(alignment: .top) {
                        content.environment(\.layoutProbesEnabled, false)
                            .fixedSize(horizontal: false, vertical: true).hidden()
                            .background(GeometryReader { g in
                                Color.clear.preference(key: LayoutIdealKey.self, value: g.size.height)
                            })
                    }
                    .backgroundPreferenceValue(LayoutIdealKey.self) { ideal in report(ideal: ideal) }
                    .transformPreference(LayoutIdealKey.self) { $0 = nil }
            } else {
                content.background(report(ideal: nil))
            }
        } else {
            content
        }
    }

    private func report(ideal: CGFloat?) -> some View {
        GeometryReader { g in
            Color.clear.preference(key: LayoutProbeKey.self, value: [
                LayoutProbe(id: id, frame: g.frame(in: .named(LayoutProbe.space)), rules: rules, idealHeight: ideal),
            ])
        }
    }
}

public extension View {
    /// Marks the element for the layout checks (see `LayoutProbe`); does nothing in the app.
    func layoutProbe(_ id: String, row: String? = nil, inside: String? = nil, contains: String? = nil,
                     scrolls: Bool = false, checksText: Bool = false) -> some View {
        modifier(LayoutProbeModifier(id: id, rules: .init(row: row, inside: inside, contains: contains, scrolls: scrolls),
                                     checksText: checksText))
    }
}
