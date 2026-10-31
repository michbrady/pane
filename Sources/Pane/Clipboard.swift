import AppKit

/// Files on the pasteboard. Copy and Cut both write real file URLs, so Finder and
/// other apps can paste them. Cut also remembers the items, to move them on Paste.
@MainActor
struct Clipboard {
    private(set) var cutPaths: Set<String> = []
    private var cutChangeCount = -1
    /// Tests and snapshots use their own pasteboard, so they never touch yours.
    private var pasteboard: NSPasteboard {
        Locations.isOverridden ? NSPasteboard(name: NSPasteboard.Name("com.michaelbrady.pane.test")) : .general
    }

    mutating func write(_ urls: [URL], cut: Bool) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        cutPaths = cut ? Set(urls.map(\.standardizedFileURL.path)) : []
        cutChangeCount = pasteboard.changeCount
    }

    var urls: [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    /// True while the pasteboard still holds what was cut.
    var isCutActive: Bool {
        !cutPaths.isEmpty && pasteboard.changeCount == cutChangeCount
    }

    func isCut(_ url: URL) -> Bool {
        isCutActive && cutPaths.contains(url.standardizedFileURL.path)
    }

    mutating func clearCut() {
        cutPaths = []
    }
}
