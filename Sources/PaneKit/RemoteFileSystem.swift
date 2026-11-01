import Foundation

public enum RemoteError: Error, Equatable, Sendable {
    /// The server went away, or the connection dropped. The tab offers Reconnect.
    case connectionLost
    /// No connection is open to that server.
    case notConnected
    /// The server said no, with its reason.
    case denied(String)
    /// A server Pane has not seen before. `keyLine` is what to remember if the person trusts it.
    case unknownHostKey(fingerprint: String, keyLine: String)
    /// The server's key is not the one Pane remembered. Never connect past this.
    case hostKeyChanged
    case other(String)
}

extension RemoteError {
    /// What to tell the person.
    public var message: String {
        switch self {
        case .connectionLost, .notConnected: "Unable to reach the server."
        case .denied(let reason), .other(let reason): reason
        case .unknownHostKey: "Pane does not know this server yet."
        case .hostKeyChanged: "This server's key changed since you last connected. Pane stopped, in case it is not the same server."
        }
    }
}

/// A file system on a server. FTP, SFTP, and S3 each provide one. It works on URLs like
/// `sftp://host/folder`, so the rest of Pane treats it like any other place.
public typealias ByteProgress = @Sendable (Int64) -> Void

public protocol RemoteFileSystem: FileSystem {
    /// Copies a file from the server to `local`, calling `progress` with the bytes so far.
    /// Stops early, and throws, when the task is cancelled. The caller removes what was half written.
    func download(_ remote: URL, to local: URL, progress: @escaping ByteProgress) async throws
    /// Copies a file to the server. The file appears under its name only when it is whole, so a cancelled
    /// or failed upload leaves nothing behind. `replacing` is true when a file is already there.
    func upload(_ local: URL, to remote: URL, replacing: Bool, progress: @escaping ByteProgress) async throws
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
    private var contents: [String: Data] = [:]
    private var transferDelay: Duration = .zero
    private var failing: Set<String> = []

    public init(serverKey: String) {
        self.serverKey = serverKey
    }

    /// Adds a folder or file at a path on the server, like "/Documents/a.txt".
    public func add(folder path: String) { inner.add(folder: path) }
    public func add(file path: String, size: Int64 = 1) { inner.add(file: path, size: size) }

    /// Makes the next listings fail as if the connection dropped, until `reconnect()`.
    public func dropConnection() { lock.withLock { lost = true } }

    /// A file with real bytes, so a download can be compared byte for byte.
    public func add(file path: String, contents data: Data) {
        inner.add(file: path, size: Int64(data.count))
        lock.withLock { contents[path] = data }
    }

    /// The bytes of a file on the server, or nil.
    public func data(at path: String) -> Data? { lock.withLock { contents[path] } }

    /// Paths on the server that exist now, for tests.
    public func paths() -> [String] { inner.paths().filter { !$0.hasPrefix("/.Trash") && $0 != "/" } }

    /// Makes each 1 KB of a transfer take this long, so a test can cancel one midway.
    public func slowTransfers(by delay: Duration) { lock.withLock { transferDelay = delay } }

    /// Makes uploads and downloads of these server paths fail.
    public func failTransfers(of paths: Set<String>) { lock.withLock { failing = paths } }

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

    public func remove(_ url: URL) async throws {
        guard !isLost else { throw RemoteError.connectionLost }
        let path = RemoteURL.canonical(url).path
        try await inner.remove(innerURL(url))
        lock.withLock { for key in contents.keys where key == path || key.hasPrefix(path + "/") { contents[key] = nil } }
    }

    public func makeFolder(_ url: URL) async throws {
        guard !isLost else { throw RemoteError.connectionLost }
        try await inner.makeFolder(innerURL(url))
    }

    public func download(_ remote: URL, to local: URL, progress: @escaping ByteProgress) async throws {
        guard !isLost else { throw RemoteError.connectionLost }
        let path = RemoteURL.canonical(remote).path
        let (data, delay, fails) = lock.withLock { (contents[path], transferDelay, failing.contains(path)) }
        guard let data else { throw RemoteError.other("That file does not exist.") }
        FileManager.default.createFile(atPath: local.path, contents: nil)
        let handle = try FileHandle(forWritingTo: local)
        defer { try? handle.close() }
        if fails {
            // A server that drops partway: half the file arrives, then the connection is gone.
            try handle.write(contentsOf: data.prefix(data.count / 2))
            throw RemoteError.connectionLost
        }
        var sent = 0
        while sent < data.count {
            try Task.checkCancellation()
            if delay != .zero { try await Task.sleep(for: delay) }
            let end = min(sent + 1024, data.count)
            try handle.write(contentsOf: data[sent..<end])
            sent = end
            progress(Int64(sent))
        }
    }

    public func upload(_ local: URL, to remote: URL, replacing: Bool, progress: @escaping ByteProgress) async throws {
        guard !isLost else { throw RemoteError.connectionLost }
        let path = RemoteURL.canonical(remote).path
        let (delay, fails) = lock.withLock { (transferDelay, failing.contains(path)) }
        let data = try Data(contentsOf: local)
        if fails { throw RemoteError.connectionLost }
        var received = 0
        while received < data.count {
            try Task.checkCancellation()
            if delay != .zero { try await Task.sleep(for: delay) }
            received = min(received + 1024, data.count)
            progress(Int64(received))
        }
        // Only a whole file appears. A cancelled upload never reaches this line.
        if replacing { try? await inner.remove(innerURL(remote)) }
        add(file: path, contents: data)
    }
}
