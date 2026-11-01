import AppKit
import PaneKit
import SwiftUI

/// Box selection for the Details and List views. The list is a SwiftUI `Table` on an AppKit table, which has
/// no box of its own, so a mouse monitor starts one when a click lands on empty space inside it (below the rows).
/// Rows are the same `RubberBand` rule the Icons view uses. Command or Shift adds to what was selected.
struct DetailsRubberBand: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {}

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.remove() }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private var monitor: Any?
        private var drag: (table: NSTableView, start: CGPoint, base: IndexSet, additive: Bool)?
        private var band: BandView?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                // The result is only whether the event was used, because an event cannot cross actors.
                let used = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return used ? nil : event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            finish()
        }

        /// True when the box used the event, so nothing else should see it.
        private func handle(_ event: NSEvent) -> Bool {
            switch event.type {
            case .leftMouseDown:
                guard drag == nil, event.clickCount == 1, let table = emptySpaceTable(under: event) else { return false }
                // The keys are read now, in the event.
                let additive = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
                let point = table.convert(event.locationInWindow, from: nil)
                drag = (table, point, additive ? table.selectedRowIndexes : [], additive)
                // A plain click on empty space clears the selection, like it always did.
                if !additive { table.deselectAll(nil) }
                return true
            case .leftMouseDragged:
                guard let drag else { return false }
                let raw = drag.table.convert(event.locationInWindow, from: nil)
                let bounds = drag.table.bounds
                let point = CGPoint(x: min(max(raw.x, bounds.minX), bounds.maxX), y: min(max(raw.y, bounds.minY), bounds.maxY))
                guard RubberBand.isDrag(from: drag.start, to: point) else { return true }
                let box = RubberBand.rect(from: drag.start, to: point)
                show(box, in: drag.table)
                let rows = (0..<drag.table.numberOfRows).map { (id: $0, frame: drag.table.rect(ofRow: $0)) }
                let chosen = RubberBand.selection(in: box, frames: rows, base: Set(drag.base), additive: drag.additive)
                drag.table.selectRowIndexes(IndexSet(chosen), byExtendingSelection: false)
                drag.table.autoscroll(with: event)
                return true
            case .leftMouseUp:
                guard drag != nil else { return false }
                finish()
                return true
            default:
                return false
            }
        }

        /// The list's table, when the click is below its last row. The Navigation pane's table and the header do not count.
        private func emptySpaceTable(under event: NSEvent) -> NSTableView? {
            guard let window = event.window, let top = window.contentView?.superview,
                  var view = top.hitTest(event.locationInWindow) else { return nil }
            if view is NSTableHeaderView || view is NSScroller { return nil }
            while !(view is NSTableView) {
                guard let parent = view.superview else { return nil }
                view = parent
            }
            guard let table = view as? NSTableView, table === FocusMover.listTable(in: window) else { return nil }
            let point = table.convert(event.locationInWindow, from: nil)
            return table.row(at: point) == -1 && table.visibleRect.contains(point) ? table : nil
        }

        private func show(_ box: CGRect, in table: NSTableView) {
            if band == nil {
                let view = BandView(frame: box)
                table.addSubview(view)
                band = view
            }
            band?.frame = box
        }

        private func finish() {
            band?.removeFromSuperview()
            band = nil
            drag = nil
        }
    }
}

/// The box that follows the pointer: a pale wash of the accent color with a thin edge.
private final class BandView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        bounds.fill()
        NSColor.controlAccentColor.setStroke()
        let edge = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        edge.lineWidth = 1
        edge.stroke()
    }
}
