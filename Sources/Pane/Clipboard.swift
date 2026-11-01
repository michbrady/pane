import AppKit
import PaneKit

/// Files on the pasteboard. Copy and Cut both write real file URLs, so Finder and
/// other apps can paste them. Cut also remembers the items, to move them on Paste.
@MainActor
struct Clipboard {
    private(set) var cutPaths: Set<String> = []
    private var cutChangeCount = -1
    /// Items copied from a server. The pasteboard only holds real files, so these stay in the app,
    /// for as long as the pasteboard has not changed since.
    private var remoteURLs: [URL] = []
    private var remoteChangeCount = -1
    /// Tests and snapshots use their own pasteboard, so they never touch yours.
    private var pasteboard: NSPasteboard {
        Locations.isOverridden ? NSPasteboard(name: NSPasteboard.Name("com.michaelbrady.pane.test")) : .general
    }

    mutating func write(_ urls: [URL], cut: Bool) {
        pasteboard.clearContents()
        if urls.contains(where: RemoteURL.isRemote) {
            // Other apps get the addresses as text. Pane gets the items back from `remoteURLs`.
            pasteboard.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
            remoteURLs = urls
            remoteChangeCount = pasteboard.changeCount
        } else {
            pasteboard.writeObjects(urls as [NSURL])
            remoteURLs = []
        }
        cutPaths = cut ? Set(urls.map(Self.key)) : []
        cutChangeCount = pasteboard.changeCount
    }

    /// One spelling per item: a server address as it is, a file by its path.
    private static func key(_ url: URL) -> String {
        RemoteURL.isRemote(url) ? RemoteURL.canonical(url).absoluteString : url.standardizedFileURL.path
    }

    var urls: [URL] {
        if !remoteURLs.isEmpty, pasteboard.changeCount == remoteChangeCount { return remoteURLs }
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    /// True while the pasteboard still holds what was cut.
    var isCutActive: Bool {
        !cutPaths.isEmpty && pasteboard.changeCount == cutChangeCount
    }

    func isCut(_ url: URL) -> Bool {
        isCutActive && cutPaths.contains(Self.key(url))
    }

    mutating func clearCut() {
        cutPaths = []
    }
}
