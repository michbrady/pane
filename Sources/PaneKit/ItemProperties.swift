import Foundation

/// What the Properties panel shows about one item.
public struct ItemProperties: Sendable, Equatable {
    public let name: String
    public let kind: String
    public let location: String
    public let isFolder: Bool
    /// Bytes in a file. nil for a folder, which is measured separately.
    public let size: Int64?
    /// Bytes the file takes on disk, which is more than its size because of block rounding.
    public let sizeOnDisk: Int64?
    public let created: Date?
    public let modified: Date?
    /// Like "rw-r--r--".
    public let permissions: String
    public let tags: [String]

    public static func read(_ url: URL) -> ItemProperties? {
        let keys: Set<URLResourceKey> = [.nameKey, .localizedTypeDescriptionKey, .isDirectoryKey, .isPackageKey, .fileSizeKey,
                                         .totalFileAllocatedSizeKey, .creationDateKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let isFolder = (values.isDirectory ?? false) && !(values.isPackage ?? false)
        let posix = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? 0
        return ItemProperties(
            name: values.name ?? url.lastPathComponent,
            kind: isFolder ? "File folder" : (values.localizedTypeDescription ?? "File"),
            location: url.deletingLastPathComponent().path,
            isFolder: isFolder,
            size: isFolder ? nil : values.fileSize.map(Int64.init),
            sizeOnDisk: isFolder ? nil : values.totalFileAllocatedSize.map(Int64.init),
            created: values.creationDate,
            modified: values.contentModificationDate,
            permissions: permissionText(posix),
            tags: TagEditor.tags(of: url))
    }

    /// 0o644 becomes "rw-r--r--".
    public static func permissionText(_ posix: Int) -> String {
        let letters = Array("rwxrwxrwx")
        return String((0..<9).map { posix & (1 << (8 - $0)) != 0 ? letters[$0] : "-" })
    }
}

/// The total of a folder and everything in it. It can take a while, so it checks `isCancelled`.
public struct FolderTotal: Sendable, Equatable {
    public var bytes: Int64 = 0
    public var bytesOnDisk: Int64 = 0
    public var files = 0
    public var folders = 0

    public init() {}

    public static func measure(_ url: URL, isCancelled: () -> Bool = { false }) -> FolderTotal {
        var total = FolderTotal()
        let keys: [URLResourceKey] = [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey, .isPackageKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                                          errorHandler: { _, _ in true }) else { return total }
        while let next = walker.nextObject() as? URL {
            if isCancelled() { break }
            guard let values = try? next.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true, values.isPackage != true {
                total.folders += 1
            } else {
                total.files += 1
                total.bytes += Int64(values.fileSize ?? 0)
                total.bytesOnDisk += Int64(values.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }

    /// Measures on a background thread, so the panel stays responsive. A cancelled task stops early.
    public static func measureInBackground(_ url: URL) async -> FolderTotal {
        await Task.detached { measure(url, isCancelled: { Task.isCancelled }) }.value
    }
}
