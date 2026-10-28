import SwiftUI

// Mely's visual language (task 7.1, ux-proposal.md → «Визуальный язык»): every screen of
// the island takes its sizes, inks, fills, radii and motion from here.

/// Text sizes on the island.
public enum MelyType {
    public static let micro: CGFloat = 9.5
    public static let caption: CGFloat = 10.5
    public static let footnote: CGFloat = 11.5
    public static let body: CGFloat = 12.5
    public static let title: CGFloat = 13
    public static let headline: CGFloat = 15
    public static let display: CGFloat = 17
}

/// Text on black: how much white.
public enum MelyInk {
    public static let primary = 0.92
    public static let strong = 0.7
    public static let secondary = 0.55
    public static let tertiary = 0.4
    public static let faint = 0.28
}

/// Surfaces on black: how much white.
public enum MelyFill {
    public static let card = 0.06
    public static let raised = 0.1
    public static let selected = 0.15
    public static let border = 0.1
}

public enum MelyRadius {
    public static let small: CGFloat = 6
    public static let medium: CGFloat = 10
    public static let large: CGFloat = 14
    public static let island: CGFloat = 24
}

public enum MelySpace {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 6
    public static let m: CGFloat = 8
    public static let l: CGFloat = 12
    public static let xl: CGFloat = 16
    public static let xxl: CGFloat = 20
}

/// Colours that mean something.
public enum MelyTint {
    public static let working = Color(red: 0.36, green: 0.56, blue: 1.0)
    public static let done = Color(red: 0.3, green: 0.8, blue: 0.45)
    public static let approval = Color(red: 1.0, green: 0.6, blue: 0.2)
    public static let question = Color(red: 0.65, green: 0.55, blue: 0.98)
    public static let error = Color(red: 1.0, green: 0.38, blue: 0.35)
    public static let limit = Color(red: 0.95, green: 0.75, blue: 0.2)
    public static let music = Color(red: 0.93, green: 0.36, blue: 0.6)
    /// A focus session: a warm orange, redder than an approval; red means an error.
    public static let focus = Color(red: 1.0, green: 0.48, blue: 0.28)
    /// A focus break.
    public static let rest = Color(red: 0.3, green: 0.8, blue: 0.76)
}

public enum MelyMotion {
    /// The island's shape between notch, preview and open.
    public static let island = Animation.spring(response: 0.42, dampingFraction: 0.8)
    /// Content comes in once the shape has moved.
    public static let contentIn = Animation.easeOut(duration: 0.18).delay(0.12)
    /// Content leaves before the shape does.
    public static let contentOut = Animation.easeIn(duration: 0.1)
    public static let hover = Animation.easeOut(duration: 0.15)
    public static let press = Animation.spring(response: 0.3, dampingFraction: 0.7)
    public static let tab = Animation.easeOut(duration: 0.15)
}
