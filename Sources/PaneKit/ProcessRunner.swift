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

    public func run(_ executable: String, _ arguments: [String], input: String, environment: [String: String]) async throws -> ProcessResult {
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
                do { try process.run() } catch {
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
    }
}
