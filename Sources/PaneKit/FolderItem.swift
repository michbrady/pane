import Foundation

/// One row in a folder listing: a file or a folder.
public struct FolderItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    /// True for folders. Packages (like .app bundles) count as files.
    public let isFolder: Bool
    /// Bytes. nil for folders.
    public let size: Int64?
    public let modified: Date?
    /// The localized kind, like "PDF Document".
    public let kind: String
    public let created: Date?
    /// Finder tag names, like "Red" or "Work".
    public let tags: [String]
    /// In the cloud but not yet on this Mac: opening it downloads it first.
    public let isOnlineOnly: Bool

    public var id: URL { url }

    public init(url: URL, name: String, isFolder: Bool, size: Int64?, modified: Date?, kind: String,
                created: Date? = nil, tags: [String] = [], isOnlineOnly: Bool = false) {
        self.url = url
        self.name = name
        self.isFolder = isFolder
        self.size = size
        self.modified = modified
        self.kind = kind
        self.created = created
        self.tags = tags
        self.isOnlineOnly = isOnlineOnly
    }
}
