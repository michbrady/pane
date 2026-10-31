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
    public init() {}

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
