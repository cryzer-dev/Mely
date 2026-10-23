import SwiftUI

/// The open island fits its page: each page counts the heights of its parts (a list's
/// rows, a bar under them), the overview passes on the page on screen, and the island
/// grows up to its full height, past which the lists scroll.

/// Heights of a page's parts, summed.
struct IslandPartHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

/// What the page on screen needs below the header; `.infinity`: all the island has
/// (the chat, a request card); nil: nobody said, all of it too.
public struct IslandContentHeightKey: PreferenceKey {
    public static let defaultValue: CGFloat? = nil
    public static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

extension View {
    /// Counts this view's height, plus the `spacing` above it, into its page's height.
    func islandPart(spacing: CGFloat = 0) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: IslandPartHeightKey.self, value: geo.size.height + spacing)
        })
    }
}

/// How low the left column (Mely and what hangs under it) reaches in the page; the island
/// is never shorter. The deepest one wins.
struct IslandColumnHeightKey: PreferenceKey {
    static let space = "island.page"
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
