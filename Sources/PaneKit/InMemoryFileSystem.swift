import Foundation

/// A file system in memory, for tests. Paths are plain strings, and the Trash is `/.Trash`.
public final class InMemoryFileSystem: FileSystem, @unchecked Sendable {
    private struct Node { var isFolder: Bool; var size: Int64 }
    private var nodes: [String: Node] = ["/": Node(isFolder: true, size: 0), "/.Trash": Node(isFolder: true, size: 0)]
    private let lock = NSLock()
    /// Paths whose copy or move should fail, to test cleanup.
    public var failingPaths: Set<String> = []

    public init() {}

    public func add(folder path: String) {
        lock.withLock { nodes[path] = Node(isFolder: true, size: 0) }
    }

    public func add(file path: String, size: Int64 = 1) {
        lock.withLock { nodes[path] = Node(isFolder: false, size: size) }
    }

    public func paths() -> [String] {
        lock.withLock { nodes.keys.sorted() }
    }

    public func exists(_ url: URL) async -> Bool {
        lock.withLock { nodes[url.path] != nil }
    }

    public func list(_ folder: URL) async throws -> [FolderItem] {
        lock.withLock {
            let prefix = folder.path == "/" ? "/" : folder.path + "/"
            let items = nodes.compactMap { path, node -> FolderItem? in
                guard path.hasPrefix(prefix), path != folder.path, !path.dropFirst(prefix.count).contains("/") else { return nil }
                let url = URL(fileURLWithPath: path)
                return FolderItem(url: url, name: url.lastPathComponent, isFolder: node.isFolder,
                                  size: node.isFolder ? nil : node.size, modified: nil, kind: node.isFolder ? "File folder" : "File")
            }
            return FolderLister.sorted(items)
        }
    }

    public func copy(_ source: URL, to destination: URL) async throws {
        try lock.withLock {
            if failingPaths.contains(source.path) { throw CocoaError(.fileWriteUnknown) }
            guard nodes[source.path] != nil else { throw CocoaError(.fileNoSuchFile) }
            guard nodes[destination.path] == nil else { throw CocoaError(.fileWriteFileExists) }
            for (path, node) in nodes where path == source.path || path.hasPrefix(source.path + "/") {
                nodes[destination.path + path.dropFirst(source.path.count)] = node
            }
        }
    }

    public func move(_ source: URL, to destination: URL) async throws {
        try await copy(source, to: destination)
        try await remove(source)
    }

    public func trash(_ url: URL) async throws -> URL? {
        var name = url.lastPathComponent
        var target = "/.Trash/" + name
        var n = 2
        while await exists(URL(fileURLWithPath: target)) { name = "\(url.lastPathComponent) \(n)"; target = "/.Trash/" + name; n += 1 }
        try await move(url, to: URL(fileURLWithPath: target))
        return URL(fileURLWithPath: target)
    }

    public func remove(_ url: URL) async throws {
        try lock.withLock {
            guard nodes[url.path] != nil else { throw CocoaError(.fileNoSuchFile) }
            for path in nodes.keys where path == url.path || path.hasPrefix(url.path + "/") { nodes[path] = nil }
        }
    }

    public func makeFolder(_ url: URL) async throws {
        try lock.withLock {
            guard nodes[url.path] == nil else { throw CocoaError(.fileWriteFileExists) }
            nodes[url.path] = Node(isFolder: true, size: 0)
        }
    }
}
