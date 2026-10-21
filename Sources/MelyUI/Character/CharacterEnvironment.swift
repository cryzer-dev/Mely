import SwiftUI
import MelyCore

private struct CharacterAppearanceKey: EnvironmentKey {
    static let defaultValue = CharacterAppearance()
}

public extension EnvironmentValues {
    /// The chosen look with its settings and clothes; every character view below draws it.
    var characterAppearance: CharacterAppearance {
        get { self[CharacterAppearanceKey.self] }
        set { self[CharacterAppearanceKey.self] = newValue }
    }
}

/// Carrying Mely out of the island (task 6.8): screen points, AppKit coordinates.
public struct CharacterDrag: Sendable {
    public var began: @MainActor @Sendable (CGPoint) -> Void
    public var moved: @MainActor @Sendable (CGPoint) -> Void
    public var ended: @MainActor @Sendable (CGPoint) -> Void
    /// Mely is out on the desktop: its spot in the island stays empty.
    public var isAway: Bool
    /// Brings it back from the desktop.
    public var callHome: @MainActor @Sendable () -> Void

    public init(isAway: Bool = false, began: @escaping @MainActor @Sendable (CGPoint) -> Void, moved: @escaping @MainActor @Sendable (CGPoint) -> Void,
                ended: @escaping @MainActor @Sendable (CGPoint) -> Void, callHome: @escaping @MainActor @Sendable () -> Void) {
        self.isAway = isAway
        self.began = began
        self.moved = moved
        self.ended = ended
        self.callHome = callHome
    }
}

private struct CharacterDragKey: EnvironmentKey {
    static let defaultValue: CharacterDrag? = nil
}

public extension EnvironmentValues {
    /// Set by the app; nil where Mely cannot be carried (settings, snapshots).
    var characterDrag: CharacterDrag? {
        get { self[CharacterDragKey.self] }
        set { self[CharacterDragKey.self] = newValue }
    }
}
