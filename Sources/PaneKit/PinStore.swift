import Foundation

/// The folders pinned to Quick access. Each pin is a macOS bookmark, so a pinned
/// folder that was renamed or moved still opens.
public struct PinStore {
    public private(set) var bookmarks: [Data]

    /// `saved` is what was stored last time. With nothing stored, `defaults` are pinned.
    public init(saved: [Data]?, defaults: [URL]) {
        var data = saved ?? defaults.compactMap(Self.bookmark)
        // A bookmark whose target moved comes back stale: store the new one.
        data = data.map { old in
            guard let (url, stale) = Self.resolve(old), stale, let fresh = Self.bookmark(url) else { return old }
            return fresh
        }
        bookmarks = data
    }

    /// The pinned folders, in order. A pin whose folder is gone is skipped.
    public var urls: [URL] {
        bookmarks.compactMap { Self.resolve($0)?.url }.filter { Self.isFolder($0) }
    }

    public func contains(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return urls.contains { $0.standardizedFileURL.path == path }
    }

    public mutating func pin(_ url: URL, at index: Int? = nil) {
        guard Self.isFolder(url), !contains(url), let data = Self.bookmark(url) else { return }
        bookmarks.insert(data, at: min(max(index ?? bookmarks.count, 0), bookmarks.count))
    }

    public mutating func unpin(_ url: URL) {
        let path = url.standardizedFileURL.path
        bookmarks.removeAll { Self.resolve($0)?.url.standardizedFileURL.path == path }
    }

    static func bookmark(_ url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ data: Data) -> (url: URL, stale: Bool)? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return (url, stale)
    }

    static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
