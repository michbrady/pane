import Foundation
import UniformTypeIdentifiers

/// Reads a folder from disk. Folders come first, then names in natural order
/// ("file2" before "file10").
public enum FolderLister {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey,
        .contentModificationDateKey, .creationDateKey, .tagNamesKey, .localizedTypeDescriptionKey, .nameKey,
    ]

    public static func list(_ folder: URL, showHidden: Bool = false) throws -> [FolderItem] {
        // Hidden files are read too: an old iCloud stub is a hidden file that stands for a real one.
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])
        let items = urls.compactMap { url -> FolderItem? in
            let name = url.lastPathComponent
            if let real = OnlineStatus.realName(ofPlaceholder: name) { return placeholder(at: url, realName: real) }
            if !showHidden, name.hasPrefix(".") { return nil }
            return item(at: url)
        }
        return sorted(items)
    }

    /// An old iCloud stub, shown under the real file's name, size, and kind.
    static func placeholder(at url: URL, realName: String) -> FolderItem? {
        guard let stub = item(at: url) else { return nil }
        let real = url.deletingLastPathComponent().appending(path: realName)
        // The real file is not here, so its kind comes from its extension.
        let kind = UTType(filenameExtension: real.pathExtension)?.localizedDescription ?? "File"
        return FolderItem(url: real, name: realName, isFolder: false, size: OnlineStatus.size(ofPlaceholderAt: url),
                          modified: stub.modified, kind: kind, created: stub.created, tags: [], isOnlineOnly: true)
    }

    public static func item(at url: URL) -> FolderItem? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        var isFolder = (values.isDirectory ?? false) && !(values.isPackage ?? false)
        // A link to a folder opens like a folder.
        if values.isSymbolicLink == true {
            var isDirectory: ObjCBool = false
            let target = url.resolvingSymlinksInPath().path
            isFolder = FileManager.default.fileExists(atPath: target, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        return FolderItem(
            url: url,
            name: values.name ?? url.lastPathComponent,
            isFolder: isFolder,
            size: isFolder ? nil : values.fileSize.map(Int64.init),
            modified: values.contentModificationDate,
            kind: isFolder ? "File folder" : (values.localizedTypeDescription ?? "File"),
            created: values.creationDate,
            tags: values.tagNames ?? [],
            isOnlineOnly: !isFolder && OnlineStatus.isOnlineOnly(url))
    }

    public static func sorted(_ items: [FolderItem]) -> [FolderItem] {
        items.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
