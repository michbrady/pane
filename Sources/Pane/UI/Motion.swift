import SwiftUI

/// Every animation goes through here, so Reduce Motion applies everywhere.
enum Motion {
    /// Hover fills on rows and buttons.
    static let hover: Animation = .easeOut(duration: 0.12)
    /// Presses and small flips (a disclosure arrow turning).
    static let quick: Animation = .easeOut(duration: 0.15)
    /// Panes opening and closing (Preview pane).
    static let ui: Animation = .smooth(duration: 0.25)
    /// Rows added to or removed from a list.
    static let listChange: Animation = .smooth(duration: 0.2)
}
