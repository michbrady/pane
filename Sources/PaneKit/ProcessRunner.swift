import Foundation

public struct ProcessResult: Sendable, Equatable {
    public let stdout: String
    public let stderr: String
    public let status: Int32
    public init(stdout: String, stderr: String, status: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.status = status
    }
}

/// Runs a command line tool. SFTP uses the system `sftp` through this, and tests give a stub.
public protocol ProcessRunner: Sendable {
    func run(_ executable: String, _ arguments: [String], input: String, environment: [String: String]) async throws -> ProcessResult
}

public struct SystemProcessRunner: ProcessRunner {
    public init() {}

    /// Holds the running process, so a cancelled task can stop it.
    private final class Running: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false
        var wasCancelled: Bool { lock.withLock { cancelled } }

        /// False when the task was cancelled before the process could start.
        func start(_ process: Process) throws -> Bool {
            try lock.withLock {
                if cancelled { return false }
                try process.run()
                self.process = process
                return true
            }
        }

        func cancel() {
            lock.withLock {
                cancelled = true
                if process?.isRunning == true { process?.terminate() }
            }
        }
    }

    public func run(_ executable: String, _ arguments: [String], input: String, environment: [String: String]) async throws -> ProcessResult {
        let running = Running()
        let result: ProcessResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
                    let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
                    process.standardInput = stdin
                    process.standardOutput = stdout
                    process.standardError = stderr
                    do {
                        guard try running.start(process) else { continuation.resume(throwing: CancellationError()); return }
                    } catch {
                        continuation.resume(throwing: RemoteError.other("Unable to start \(URL(fileURLWithPath: executable).lastPathComponent)."))
                        return
                    }
                    // Read both pipes while the tool runs, or a big listing fills the pipe and the tool stalls.
                    var out = Data(), err = Data()
                    let group = DispatchGroup()
                    for (pipe, store) in [(stdout, 0), (stderr, 1)] {
                        group.enter()
                        DispatchQueue.global().async {
                            let data = pipe.fileHandleForReading.readDataToEndOfFile()
                            if store == 0 { out = data } else { err = data }
                            group.leave()
                        }
                    }
                    stdin.fileHandleForWriting.write(Data(input.utf8))
                    try? stdin.fileHandleForWriting.close()
                    group.wait()
                    process.waitUntilExit()
                    continuation.resume(returning: ProcessResult(stdout: String(decoding: out, as: UTF8.self),
                                                                stderr: String(decoding: err, as: UTF8.self), status: process.terminationStatus))
                }
            }
        } onCancel: {
            running.cancel()
        }
        if running.wasCancelled { throw CancellationError() }
        return result
    }
}

/// Watches a file grow, to report progress for a tool that does not report its own.
public enum FileGrowth {
    /// Calls `progress` with the file's size a few times a second, until the task is cancelled.
    public static func watch(_ file: URL, progress: @escaping ByteProgress) -> Task<Void, Never> {
        Task.detached {
            while !Task.isCancelled {
                if let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int64 { progress(size) }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}

extension RemoteTree {
    /// Whether something is there: the name is in its folder's listing. A server's top always is.
    /// (Listing the item itself would say yes for a name that is not there, on a server with no real folders.)
    public static func exists(_ url: URL, in fs: FileSystem) async -> Bool {
        guard let parent = RemoteURL.parent(of: url) else { return true }
        let name = RemoteURL.name(of: url)
        return ((try? await fs.list(parent)) ?? []).contains { $0.name == name }
    }
}

/// Removing a folder takes emptying it first. Providers whose protocol has no recursive delete use this.
public enum RemoteTree {
    public static func remove(_ url: URL, in fs: FileSystem, file: (URL) async throws -> Void, emptyFolder: (URL) async throws -> Void) async throws {
        let isFolder: Bool
        if let parent = RemoteURL.parent(of: url) {
            let name = RemoteURL.name(of: url)
            isFolder = (try await fs.list(parent)).first { $0.name == name }?.isFolder ?? false
        } else {
            isFolder = true
        }
        guard isFolder else { try await file(url); return }
        for child in try await fs.list(url) { try await remove(child.url, in: fs, file: file, emptyFolder: emptyFolder) }
        try await emptyFolder(url)
    }
}
