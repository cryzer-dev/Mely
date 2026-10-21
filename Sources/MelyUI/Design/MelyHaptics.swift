import AppKit

/// A light tap on the Force Touch trackpad for clicks in the island (task 7.4): tabs, the
/// header's buttons, a poke at Mely. Silent on mice and older trackpads.
public enum MelyHaptics {
    @MainActor public static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
