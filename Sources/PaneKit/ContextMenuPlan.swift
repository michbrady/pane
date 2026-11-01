import Foundation

/// What a right-click on items offers, in order: an icon row on top, then the list below.
/// Pure, so the rules are tested without a window.
public struct ContextMenuPlan: Equatable, Sendable {
    public enum Entry: String, CaseIterable, Sendable {
        case cut, copy, rename, delete
        case open, openWith, properties, tags
        case openInNewTab, openInTerminal, pin, unpin
    }

    /// The icon row: Cut, Copy, Rename, Delete.
    public let iconRow: [Entry]
    /// The list under it. Services from other apps follow, added by the system.
    public let items: [Entry]

    public init(selectionCount: Int, hasFolder: Bool, isOnlyFolder: Bool, onServer: Bool, isPinned: Bool, canRename: Bool = true) {
        var row: [Entry] = [.cut, .copy]
        // Rename is for one item. A server renames too, so it stays.
        if selectionCount == 1, canRename { row.append(.rename) }
        row.append(.delete)
        var list: [Entry] = [.open]
        // Open With needs apps on this Mac to open a local file. Folders and servers' files do not offer it.
        if !onServer, !hasFolder { list.append(.openWith) }
        // Properties and Tags read this Mac's file attributes, which a server's items do not have.
        if !onServer { list.append(contentsOf: [.properties, .tags]) }
        if selectionCount == 1, isOnlyFolder {
            list.append(.openInNewTab)
            if !onServer { list.append(.openInTerminal) }
            if !onServer { list.append(isPinned ? .unpin : .pin) }
        }
        iconRow = row
        items = list
    }
}
