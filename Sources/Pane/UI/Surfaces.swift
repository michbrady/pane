import SwiftUI

/// Colors for the few custom surfaces. Chrome uses system materials.
enum Surfaces {
    /// Fill behind the Address bar field. Slightly translucent so the window tint shows through.
    static var field: Color { Color(nsColor: .controlBackgroundColor).opacity(0.8) }
    /// A thin line between window parts.
    static var hairline: Color { Color(nsColor: .separatorColor) }
    /// Opacity of items that were cut and wait to be pasted.
    static let cutOpacity: Double = 0.5
}
