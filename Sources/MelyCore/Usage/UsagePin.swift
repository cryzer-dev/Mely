import Foundation

/// Whose limits the notch's ring shows: one ring, however many agents are on.
public enum UsagePin {
    /// The pinned agent while it is on, otherwise the first one on; nil with none on.
    public static func shown(enabled: [Agent], pinned: Agent?) -> Agent? {
        if let pinned, enabled.contains(pinned) { return pinned }
        return enabled.first
    }
}
