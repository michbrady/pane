import CoreGraphics
import Foundation

/// Dragging a box on empty space to select the items it touches, like Explorer.
public enum RubberBand {
    /// Moves under this many points are a click, not a box.
    public static let minimumDistance: CGFloat = 4

    /// The box between where the drag started and where the pointer is now.
    public static func rect(from start: CGPoint, to current: CGPoint) -> CGRect {
        CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    public static func isDrag(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= minimumDistance
    }

    /// What is selected while the box is dragged. A plain drag selects just the items the box touches.
    /// With Command or Shift held, they join what was selected when the drag began.
    public static func selection<ID: Hashable>(in box: CGRect, frames: [(id: ID, frame: CGRect)], base: Set<ID>, additive: Bool) -> Set<ID> {
        let touched = Set(frames.filter { $0.frame.intersects(box) }.map(\.id))
        return additive ? base.union(touched) : touched
    }
}
