import SwiftUI

/// Corner radii. Inner radius = outer radius - inset, so nested shapes stay concentric.
enum Radius {
    /// Chips and key caps.
    static let xs: CGFloat = 6
    /// Controls, the Address bar field.
    static let sm: CGFloat = 8
    /// Hover and selection fills on rows.
    static let row: CGFloat = 8
    /// Cards and the conflict sheet panels.
    static let md: CGFloat = 12
}
