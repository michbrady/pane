import Foundation
import PaneKit

/// One folder in the Navigation pane. Subfolders load the first time a row
/// asks for them, so a folder with 10,000 children costs nothing until opened.
final class NavNode: Identifiable {
    let id: String
    let url: URL
    let name: String
    /// True for an external drive or a share: the row shows an eject button.
    let ejectable: Bool
    /// A saved server that is not connected now: the row is dimmed, and a click connects.
    let isOffline: Bool
    /// The SF Symbol to show instead of a folder icon, for a connection's protocol.
    let symbol: String?
    /// Set for a saved connection, so its row can be edited or removed.
    let savedID: UUID?
    private let prefix: String
    private var loaded = false
    private var cached: [NavNode]?

    /// `prefix` keeps ids apart when one folder shows in two places ("quick:", "home:", "vol:").
    init(url: URL, prefix: String, name: String? = nil, ejectable: Bool = false,
         isOffline: Bool = false, symbol: String? = nil, savedID: UUID? = nil) {
        self.ejectable = ejectable
        self.isOffline = isOffline
        self.symbol = symbol
        self.savedID = savedID
        self.url = url.standardizedFileURL
        self.prefix = prefix
        self.id = prefix + (RemoteURL.isRemote(url) ? self.url.absoluteString : self.url.path)
        self.name = name ?? Locations.displayName(for: url)
    }

    /// Subfolders, or nil when there are none (no disclosure arrow).
    var children: [NavNode]? {
        if !loaded {
            loaded = true
            // A server's row has no folders to list here. Listing its URL as a local path would show this Mac's folders.
            if RemoteURL.isRemote(url) { return nil }
            let items = (try? FolderLister.list(url)) ?? []
            let folders = items.filter(\.isFolder).map { NavNode(url: $0.url, prefix: prefix) }
            cached = folders.isEmpty ? nil : folders
        }
        return cached
    }

    /// Forgets the subfolders of the row for this folder, wherever it shows, so they are read again.
    /// Rows already open stay open: a row's id is its path.
    func invalidate(folderAt path: String) {
        // Compared with links resolved: /tmp and /private/tmp are one folder.
        if url.resolvingSymlinksInPath().path == path { invalidate(); return }
        for child in cached ?? [] { child.invalidate(folderAt: path) }
    }

    /// Forgets every subfolder list below here.
    func invalidateAll() {
        invalidate()
    }

    func invalidate() {
        loaded = false
        cached = nil
    }
}
