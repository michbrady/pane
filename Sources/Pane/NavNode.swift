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
    private let prefix: String
    private var loaded = false
    private var cached: [NavNode]?

    /// `prefix` keeps ids apart when one folder shows in two places ("quick:", "home:", "vol:").
    init(url: URL, prefix: String, name: String? = nil, ejectable: Bool = false) {
        self.ejectable = ejectable
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

    func invalidate() {
        loaded = false
        cached = nil
    }
}
