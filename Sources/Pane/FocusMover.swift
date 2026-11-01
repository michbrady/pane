import AppKit
import PaneKit

/// Moves keyboard focus between the Navigation pane and the list by finding their tables in the window.
/// The Navigation pane is the left-most table, the list is the right-most. The Address bar is a field the model starts editing.
@MainActor
enum FocusMover {
    /// The list's table: the right-most one in the window.
    static func listTable(in window: NSWindow?) -> NSTableView? { tables(in: window).last }

    private static func tables(in window: NSWindow?) -> [NSTableView] {
        var found: [NSTableView] = []
        func walk(_ view: NSView) {
            if let table = view as? NSTableView { found.append(table) }
            view.subviews.forEach(walk)
        }
        if let root = window?.contentView { walk(root) }
        return found.filter { !$0.isHidden && $0.window != nil }.sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
    }

    /// With no window to look at, the pane counts as shown.
    static var navigationShown: Bool { NSApp.keyWindow == nil || tables(in: NSApp.keyWindow).count > 1 }

    /// Gives focus to the Navigation pane or the list. False when the window has no such table (Icons view has no list table).
    @discardableResult
    static func focus(_ region: FocusRegion) -> Bool {
        let all = tables(in: NSApp.keyWindow)
        let target = region == .navigation ? (all.count > 1 ? all.first : nil) : all.last
        guard let table = target else { return false }
        return table.window?.makeFirstResponder(table) ?? false
    }

    /// Where focus really is, when the first responder is inside one of the tables.
    static var current: FocusRegion? {
        guard let window = NSApp.keyWindow, var view = window.firstResponder as? NSView else { return nil }
        let all = tables(in: window)
        while true {
            if let table = view as? NSTableView, let index = all.firstIndex(of: table) {
                return all.count > 1 && index == 0 ? .navigation : .list
            }
            guard let parent = view.superview else { return nil }
            view = parent
        }
    }
}
