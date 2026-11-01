import Foundation

public enum RemoteError: Error, Equatable, Sendable {
    /// The server went away, or the connection dropped. The tab offers Reconnect.
    case connectionLost
    /// No connection is open to that server.
    case notConnected
    /// The server said no, with its reason.
    case denied(String)
    case other(String)
}

/// A file system on a server. FTP, SFTP, and S3 each provide one. It works on URLs like
/// `sftp://host/folder`, so the rest of Pane treats it like any other place.
public protocol RemoteFileSystem: FileSystem {
    /// `scheme://host:port`, the key the router files this connection under.
    var serverKey: String { get }
    /// Opens the connection again after it was lost.
    func reconnect() async throws
    func disconnect() async
}

/// Picks the file system for a URL: this Mac for a file URL, or the open connection for a remote one.
public final class FileSystemRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var remotes: [String: any RemoteFileSystem] = [:]
    public let local: FileSystem

    public init(local: FileSystem = LocalFileSystem()) {
        self.local = local
    }

    public func register(_ system: any RemoteFileSystem) {
        lock.withLock { remotes[system.serverKey] = system }
    }

    public func remove(serverKey: String) {
        lock.withLock { remotes[serverKey] = nil }
    }

    /// The open connection a remote URL belongs to, or nil if none is open.
    public func remote(for url: URL) -> (any RemoteFileSystem)? {
        guard RemoteURL.isRemote(url) else { return nil }
        let key = RemoteURL.serverKey(url)
        return lock.withLock { remotes[key] }
    }

    public func filesystem(for url: URL) -> FileSystem? {
        RemoteURL.isRemote(url) ? remote(for: url) : local
    }

    /// The servers connected now, by key.
    public var serverKeys: [String] {
        lock.withLock { remotes.keys.sorted() }
    }
}

/// A server in memory, for tests: it answers like a real one, and can be told to drop its connection.
public final class InMemoryRemote: RemoteFileSystem, @unchecked Sendable {
    public let serverKey: String
    private let inner = InMemoryFileSystem()
    private let lock = NSLock()
    private var lost = false
    private var listDelay: Duration = .zero

    public init(serverKey: String) {
        self.serverKey = serverKey
    }

    /// Adds a folder or file at a path on the server, like "/Documents/a.txt".
    public func add(folder path: String) { inner.add(folder: path) }
    public func add(file path: String, size: Int64 = 1) { inner.add(file: path, size: size) }

    /// Makes the next listings fail as if the connection dropped, until `reconnect()`.
    public func dropConnection() { lock.withLock { lost = true } }

    /// Makes listings slow, so a test can see the loading state.
    public func slowDown(by delay: Duration) { lock.withLock { listDelay = delay } }

    public func reconnect() async throws { lock.withLock { lost = false } }
    public func disconnect() async { lock.withLock { lost = true } }

    private var isLost: Bool { lock.withLock { lost } }

    private func innerURL(_ url: URL) -> URL { URL(fileURLWithPath: RemoteURL.canonical(url).path) }

    private func outerURL(_ inner: URL, like url: URL) -> URL {
        RemoteURL.make(scheme: url.scheme ?? "sftp", host: url.host ?? "", port: url.port, user: url.user, path: inner.path)
    }

    public func exists(_ url: URL) async -> Bool {
        guard !isLost else { return false }
        return await inner.exists(innerURL(url))
    }

    public func list(_ folder: URL) async throws -> [FolderItem] {
        let delay = lock.withLock { listDelay }
        if delay != .zero { try await Task.sleep(for: delay) }
        guard !isLost else { throw RemoteError.connectionLost }
        let listed = try await inner.list(innerURL(folder))
        // The in-memory file system keeps a /.Trash folder. A server does not show one.
        return listed.filter { !$0.name.hasPrefix(".") }.map {
            FolderItem(url: outerURL($0.url, like: folder), name: $0.name, isFolder: $0.isFolder, size: $0.size, modified: $0.modified,
                       kind: FolderItem.kind(forFileNamed: $0.name, isFolder: $0.isFolder))
        }
    }

    public func copy(_ source: URL, to destination: URL) async throws { throw RemoteError.other("not supported") }
    public func move(_ source: URL, to destination: URL) async throws { throw RemoteError.other("not supported") }
    public func trash(_ url: URL) async throws -> URL? { throw RemoteError.other("not supported") }
    public func remove(_ url: URL) async throws { throw RemoteError.other("not supported") }
    public func makeFolder(_ url: URL) async throws { throw RemoteError.other("not supported") }
}
