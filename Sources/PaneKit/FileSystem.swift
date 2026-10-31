import Foundation

/// Where files live. `LocalFileSystem` is this Mac. `InMemoryFileSystem` is for
/// tests. FTP, SFTP, and S3 plug in here later, so copy, move, and undo work for all.
public protocol FileSystem: Sendable {
    func exists(_ url: URL) async -> Bool
    func list(_ folder: URL) async throws -> [FolderItem]
    func copy(_ source: URL, to destination: URL) async throws
    func move(_ source: URL, to destination: URL) async throws
    /// Moves to the Trash and returns where it went. nil when there is no Trash (remote places).
    func trash(_ url: URL) async throws -> URL?
    /// Removes for good. Used by Delete Immediately.
    func remove(_ url: URL) async throws
    func makeFolder(_ url: URL) async throws
}

public struct LocalFileSystem: FileSystem {
    /// nil uses the Mac's Trash. Tests pass a folder, so they never fill yours.
    private let trashFolder: URL?

    public init(trashFolder: URL? = nil) {
        self.trashFolder = trashFolder
    }

    public func exists(_ url: URL) async -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func list(_ folder: URL) async throws -> [FolderItem] {
        try FolderLister.list(folder)
    }

    public func copy(_ source: URL, to destination: URL) async throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func move(_ source: URL, to destination: URL) async throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func trash(_ url: URL) async throws -> URL? {
        if let trashFolder {
            try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
            var target = trashFolder.appending(path: url.lastPathComponent)
            var n = 2
            while FileManager.default.fileExists(atPath: target.path) {
                target = trashFolder.appending(path: "\(url.lastPathComponent) \(n)")
                n += 1
            }
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }

    public func remove(_ url: URL) async throws {
        try FileManager.default.removeItem(at: url)
    }

    public func makeFolder(_ url: URL) async throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }
}
