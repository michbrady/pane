import Foundation

/// When Pane explains Full Disk Access: once, and only if it is not already granted.
public enum FullDiskAccessGuide {
    public static func shouldShow(granted: Bool, shownBefore: Bool) -> Bool {
        !granted && !shownBefore
    }

    /// The one sentence on the first-run screen.
    public static let reason = "Pane needs Full Disk Access to show folders like Desktop, Documents, and your drives without asking about each one."
}
