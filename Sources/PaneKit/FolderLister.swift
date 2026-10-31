import Foundation

/// Reads a folder from disk. Folders come first, then names in natural order
/// ("file2" before "file10").
public enum FolderLister {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey,
        .contentModificationDateKey, .localizedTypeDescriptionKey, .nameKey,
    ]

    public static func list(_ folder: URL, showHidden: Bool = false) throws -> [FolderItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys,
            options: showHidden ? [] : [.skipsHiddenFiles])
        return sorted(urls.compactMap { item(at: $0) })
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
            kind: isFolder ? "File folder" : (values.localizedTypeDescription ?? "File"))
    }

    public static func sorted(_ items: [FolderItem]) -> [FolderItem] {
        items.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
