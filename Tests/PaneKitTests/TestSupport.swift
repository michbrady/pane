import Foundation
import Testing
@testable import PaneKit

// Helpers the server tests share: a scripted process runner, scratch folders, call counters.

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

final class ScriptedRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [(exe: String, args: [String], input: String, env: [String: String])] = []
    let answer: @Sendable (String, [String], String) -> ProcessResult
    init(_ answer: @escaping @Sendable (String, [String], String) -> ProcessResult) { self.answer = answer }
    func run(_ executable: String, _ arguments: [String], input: String, environment: [String: String]) async throws -> ProcessResult {
        lock.withLock { calls.append((executable, arguments, input, environment)) }
        return answer(executable, arguments, input)
    }
}

func sftpSystem(_ runner: ProcessRunner, login: SFTPFileSystem.Login = .password("pw"), known: URL? = nil) -> SFTPFileSystem {
    SFTPFileSystem(host: "NAS.local", user: "me", login: login,
                   knownHosts: known ?? FileManager.default.temporaryDirectory.appending(path: "pane-kh-\(UUID().uuidString)"),
                   workFolder: URL(fileURLWithPath: "/tmp/pane-ssh-test"), runner: runner,
                   now: { ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")! })
}

func scratchFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "pane-xfer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func serverURL(_ path: String) -> URL { RemoteURL.make(scheme: "sftp", host: "nas", path: path) }

let skipAll: FileOperations.Resolver = { _ in ConflictDecision(choice: .skip) }

final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [OperationProgress] = []
    func add(_ value: OperationProgress) { lock.withLock { items.append(value) } }
    var values: [OperationProgress] { lock.withLock { items } }
}

final class Collected2: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ value: String) { lock.withLock { items.append(value) } }
    var values: [String] { lock.withLock { items } }
}
