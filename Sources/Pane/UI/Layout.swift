import SwiftUI

/// Fixed sizes for Pane's window parts. All on the 4 pt grid.
enum Layout {
    /// Navigation pane (sidebar) width: minimum, ideal, maximum.
    static let navigationMin: CGFloat = 200
    static let navigationIdeal: CGFloat = 240
    static let navigationMax: CGFloat = 360
    /// Preview pane (inspector) width.
    static let previewMin: CGFloat = 240
    static let previewIdeal: CGFloat = 300
    static let previewMax: CGFloat = 480
    /// The row of tabs, and one tab in it.
    static let tabStripHeight: CGFloat = 36
    static let tabHeight: CGFloat = 28
    /// The Address bar row under the toolbar.
    static let addressBarHeight: CGFloat = 36
    /// The Status bar at the bottom of the content column.
    static let statusBarHeight: CGFloat = 24
    /// One row in Details and List view, and in the Navigation pane.
    static let rowHeight: CGFloat = 24
    /// Icons view: one cell, and the icon in it.
    static let iconCell: CGFloat = 96
    static let gridIcon: CGFloat = 48
    /// Icon beside an item name in Details view.
    static let rowIcon: CGFloat = 16
    /// The conflict sheet and Properties panel.
    static let sheetWidth: CGFloat = 480
}
