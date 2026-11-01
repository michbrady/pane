import Foundation

/// Opening a file from a server: a temporary copy on this Mac, and the saves made to it going back.
/// Pure of any app: the app calls `changed()` on a timer and `sync(_:)` for each file that changed.
/// A file whose server copy changed since it was opened is never overwritten without asking.
public final class RemoteEdits: @unchecked Sendable {
    /// What a file looked like at one moment: enough to notice a change.
    public struct Stamp: Equatable, Sendable {
        public let size: Int64?
        public let modified: Date?
    }

    public struct Session: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let remote: URL
        public let local: URL
        /// The server's copy when it was opened, or last sent.
        public fileprivate(set) var server: Stamp
        /// Our copy when it was opened, or last sent.
        public fileprivate(set) var sent: Stamp
        /// Our copy when the person said "not now". Asked again only after another save.
        public fileprivate(set) var held: Stamp?
        public var name: String { local.lastPathComponent }
    }

    public enum Outcome: Equatable, Sendable {
        case uploaded
        /// The server's copy is not the one that was opened. Nothing was sent.
        case serverChanged
        case unchanged
    }

    private let router: FileSystemRouter
    private let root: URL
    private let lock = NSLock()
    private var sessions: [UUID: Session] = [:]

    /// `root` is a folder for the temporary copies. Everything in it is removed by `discardAll()`.
    public init(router: FileSystemRouter, root: URL) {
        self.router = router
        self.root = root
    }

    // MARK: Opening

    /// Downloads the file to a temporary folder and starts watching it. Returns the copy's address.
    public func open(_ remote: URL, progress: @escaping ByteProgress) async throws -> URL {
        guard let server = router.remote(for: remote) else { throw RemoteError.notConnected }
        guard let item = try await Self.item(remote, in: server) else { throw RemoteError.other("That file does not exist.") }
        let folder = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let local = folder.appending(path: item.name)
        do { try await server.download(remote, to: local, progress: progress) } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        let session = Session(id: UUID(), remote: remote, local: local, server: Stamp(size: item.size, modified: item.modified),
                              sent: Self.stamp(local), held: nil)
        lock.withLock { sessions[session.id] = session }
        return local
    }

    // MARK: Watching

    /// The files saved since they were opened or last sent, and not put on hold.
    public func changed() -> [Session] {
        lock.withLock { Array(sessions.values) }.filter { session in
            let now = Self.stamp(session.local)
            return now != session.sent && now != session.held
        }
    }

    public var hasUnsent: Bool { !changed().isEmpty }
    public var isEmpty: Bool { lock.withLock { sessions.isEmpty } }

    /// Sends a saved file back. With `replacing`, the server's copy is overwritten even if it changed.
    public func sync(_ id: UUID, replacing: Bool = false) async throws -> Outcome {
        guard let session = lock.withLock({ sessions[id] }) else { return .unchanged }
        let now = Self.stamp(session.local)
        guard now != session.sent else { return .unchanged }
        guard let server = router.remote(for: session.remote) else { throw RemoteError.notConnected }
        if !replacing {
            let current = try await Self.item(session.remote, in: server)
            if Stamp(size: current?.size, modified: current?.modified) != session.server { return .serverChanged }
        }
        try await server.upload(session.local, to: session.remote, replacing: true, progress: { _ in })
        let after = try await Self.item(session.remote, in: server)
        lock.withLock {
            sessions[id]?.sent = now
            sessions[id]?.held = nil
            sessions[id]?.server = Stamp(size: after?.size, modified: after?.modified)
        }
        return .uploaded
    }

    /// "Not now": leave the file as it is, and ask again only after the next save.
    public func hold(_ id: UUID) {
        lock.withLock { if let session = sessions[id] { sessions[id]?.held = Self.stamp(session.local) } }
    }

    /// Removes every temporary copy. Called when Pane quits.
    public func discardAll() {
        lock.withLock { sessions = [:] }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    static func stamp(_ file: URL) -> Stamp {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        return Stamp(size: (attributes?[.size] as? NSNumber)?.int64Value, modified: attributes?[.modificationDate] as? Date)
    }

    private static func item(_ url: URL, in server: FileSystem) async throws -> FolderItem? {
        guard let parent = RemoteURL.parent(of: url) else { return nil }
        let name = RemoteURL.name(of: url)
        return try await server.list(parent).first { $0.name == name }
    }
}
