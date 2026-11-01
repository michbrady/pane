import Foundation
import Testing
@testable import PaneKit

// MARK: Copy between this Mac and a server (S-064)

func transferSetup() -> (TransferOperations, InMemoryRemote, URL) {
    let router = FileSystemRouter()
    let nas = InMemoryRemote(serverKey: "sftp://nas")
    router.register(nas)
    return (TransferOperations(router: router), nas, scratchFolder())
}

@Test func statsGiveSpeedAndTimeLeft() {
    var stats = TransferStats()
    let start = Date(timeIntervalSince1970: 1000)
    stats.add(bytes: 0, at: start)
    #expect(stats.bytesPerSecond == nil)
    stats.add(bytes: 1_000_000, at: start.addingTimeInterval(1))
    #expect(stats.bytesPerSecond == 1_000_000)
    #expect(stats.secondsLeft(done: 1_000_000, total: 10_000_000) == 9)
    #expect(stats.describe(done: 1_000_000, total: 10_000_000) == "1 MB of 10 MB · 1 MB/s · 9 seconds left")
    #expect(TransferStats().describe(done: 0, total: 0) == "")
    #expect(TransferStats.words(forSeconds: 75) == "2 minutes left" && TransferStats.words(forSeconds: 7300) == "2 hr 2 min left")
}

@Test func anUploadArrivesWholeAndMatchesByteForByte() async throws {
    let (transfers, nas, local) = transferSetup()
    nas.add(folder: "/Docs")
    let bytes = Data((0..<5000).map { UInt8($0 % 251) })
    try bytes.write(to: local.appending(path: "photo.jpg"))
    let result = await transfers.paste([local.appending(path: "photo.jpg")], into: serverURL("/Docs"), mode: .copy, resolve: skipAll)
    #expect(result.failures.isEmpty && !result.wasCancelled)
    #expect(nas.data(at: "/Docs/photo.jpg") == bytes)
    #expect(FileManager.default.fileExists(atPath: local.appending(path: "photo.jpg").path))   // copy keeps the original
}

@Test func aDownloadMatchesByteForByteAndLeavesNoPartFile() async throws {
    let (transfers, nas, local) = transferSetup()
    let bytes = Data((0..<3000).map { UInt8($0 % 199) })
    nas.add(folder: "/Docs"); nas.add(file: "/Docs/report.pdf", contents: bytes)
    let result = await transfers.paste([serverURL("/Docs/report.pdf")], into: local, mode: .copy, resolve: skipAll)
    #expect(result.failures.isEmpty)
    #expect(try Data(contentsOf: local.appending(path: "report.pdf")) == bytes)
    #expect(try FileManager.default.contentsOfDirectory(atPath: local.path) == ["report.pdf"])
}

@Test func foldersGoBothWaysWithEverythingInThem() async throws {
    let (transfers, nas, local) = transferSetup()
    let tree = local.appending(path: "Trip")
    try FileManager.default.createDirectory(at: tree.appending(path: "Day 1"), withIntermediateDirectories: true)
    try Data("a".utf8).write(to: tree.appending(path: "Day 1/a.txt"))
    try Data("hidden".utf8).write(to: tree.appending(path: ".note"))
    nas.add(folder: "/Up")
    _ = await transfers.paste([tree], into: serverURL("/Up"), mode: .copy, resolve: skipAll)
    #expect(nas.paths().sorted() == ["/Up", "/Up/Trip", "/Up/Trip/.note", "/Up/Trip/Day 1", "/Up/Trip/Day 1/a.txt"])
    let back = scratchFolder()
    let result = await transfers.paste([serverURL("/Up/Trip")], into: back, mode: .copy, resolve: skipAll)
    #expect(result.failures.isEmpty)
    #expect(try String(contentsOf: back.appending(path: "Trip/Day 1/a.txt"), encoding: .utf8) == "a")
}

@Test func aConflictAsksTheSameQuestionAndHonorsReplaceSkipAndKeepBoth() async throws {
    let (transfers, nas, local) = transferSetup()
    nas.add(folder: "/Docs"); nas.add(file: "/Docs/a.txt", contents: Data("old".utf8))
    try Data("new".utf8).write(to: local.appending(path: "a.txt"))
    let source = local.appending(path: "a.txt")
    let asked = CallCounter()
    let skip = await transfers.paste([source], into: serverURL("/Docs"), mode: .copy, resolve: { conflict in
        asked.add()
        #expect(conflict.existing.path == "/Docs/a.txt" && conflict.existingItem?.size == 3)
        return ConflictDecision(choice: .skip)
    })
    #expect(asked.value == 1 && skip.skipped == [source] && nas.data(at: "/Docs/a.txt") == Data("old".utf8))
    _ = await transfers.paste([source], into: serverURL("/Docs"), mode: .copy, resolve: { _ in ConflictDecision(choice: .keepBoth) })
    #expect(nas.data(at: "/Docs/a (2).txt") == Data("new".utf8) && nas.data(at: "/Docs/a.txt") == Data("old".utf8))
    _ = await transfers.paste([source], into: serverURL("/Docs"), mode: .copy, resolve: { _ in ConflictDecision(choice: .replace) })
    #expect(nas.data(at: "/Docs/a.txt") == Data("new".utf8))
}

@Test func cutFromAServerRemovesTheOriginalOnlyAfterTheCopySucceeded() async throws {
    let (transfers, nas, local) = transferSetup()
    nas.add(folder: "/Docs"); nas.add(file: "/Docs/ok.txt", contents: Data("ok".utf8)); nas.add(file: "/Docs/bad.txt", contents: Data("a longer file".utf8))
    nas.failTransfers(of: ["/Docs/bad.txt"])
    let result = await transfers.paste([serverURL("/Docs/ok.txt"), serverURL("/Docs/bad.txt")], into: local, mode: .move, resolve: skipAll)
    #expect(nas.data(at: "/Docs/ok.txt") == nil && FileManager.default.fileExists(atPath: local.appending(path: "ok.txt").path))
    #expect(nas.data(at: "/Docs/bad.txt") != nil, "a failed copy keeps its original")
    #expect(result.failures.count == 1 && !FileManager.default.fileExists(atPath: local.appending(path: "bad.txt").path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: local.path).sorted() == ["ok.txt"], "no half file is left")
}

@Test func cancellingLeavesNoHalfFileOnEitherSide() async throws {
    let (transfers, nas, local) = transferSetup()
    nas.add(folder: "/Docs"); nas.add(file: "/Docs/big.bin", contents: Data(repeating: 7, count: 40_000))
    try Data(repeating: 9, count: 40_000).write(to: local.appending(path: "up.bin"))
    nas.slowTransfers(by: .milliseconds(20))
    let down = Task { await transfers.paste([serverURL("/Docs/big.bin")], into: local, mode: .copy, resolve: skipAll) }
    try await Task.sleep(for: .milliseconds(150))
    down.cancel()
    #expect(await down.value.wasCancelled)
    let up = Task { await transfers.paste([local.appending(path: "up.bin")], into: serverURL("/Docs"), mode: .copy, resolve: skipAll) }
    try await Task.sleep(for: .milliseconds(150))
    up.cancel()
    #expect(await up.value.wasCancelled)
    #expect(nas.data(at: "/Docs/up.bin") == nil, "a cancelled upload leaves no file on the server")
    #expect(try FileManager.default.contentsOfDirectory(atPath: local.path).sorted() == ["up.bin"], "a cancelled download leaves no part file")
}

@Test func progressReportsBytesAndTheFileName() async throws {
    let (transfers, nas, local) = transferSetup()
    nas.add(folder: "/Docs")
    try Data(repeating: 1, count: 6000).write(to: local.appending(path: "six.bin"))
    let seen = Collected()
    _ = await transfers.paste([local.appending(path: "six.bin")], into: serverURL("/Docs"), mode: .copy, resolve: skipAll, progress: { seen.add($0) })
    let last = try #require(seen.values.last)
    #expect(last.bytesDone == 6000 && last.bytesTotal == 6000 && last.done == 1)
    #expect(seen.values.contains { $0.current == "six.bin" })
}

@Test func sftpUploadsToAHiddenNameThenRenamesAndCleansUpOnFailure() async throws {
    let local = scratchFolder().appending(path: "n.txt")
    try Data("hi".utf8).write(to: local)
    let ok = ScriptedRunner { _, _, _ in ProcessResult(stdout: "", stderr: "", status: 0) }
    try await sftpSystem(ok).upload(local, to: URL(string: "sftp://nas.local/My%20Docs/n.txt")!, replacing: true, progress: { _ in })
    let lines = try #require(ok.calls.first).input.split(separator: "\n").map(String.init)
    #expect(lines.count == 3 && lines[0].hasPrefix("put \"\(local.path)\" \"/My Docs/.n.txt.pane-part-"))
    #expect(lines[1] == "-rm \"/My Docs/n.txt\"" && lines[2].hasPrefix("rename \"/My Docs/.n.txt.pane-part-") && lines[2].hasSuffix("\" \"/My Docs/n.txt\""))
    let failing = ScriptedRunner { _, _, input in
        input.hasPrefix("put") ? ProcessResult(stdout: "", stderr: "Connection reset by peer", status: 255) : ProcessResult(stdout: "", stderr: "", status: 0)
    }
    await #expect(throws: RemoteError.connectionLost) {
        try await sftpSystem(failing).upload(local, to: URL(string: "sftp://nas.local/n.txt")!, replacing: false, progress: { _ in })
    }
    #expect(failing.calls.last?.input.hasPrefix("-rm \"/.n.txt.pane-part-") == true, "the hidden file is removed")
}

@Test func ftpUploadsToAHiddenNameThenRenamesWithoutTheLoginInArguments() async throws {
    let local = scratchFolder().appending(path: "n.txt")
    try Data("hi".utf8).write(to: local)
    let runner = ScriptedRunner { _, _, _ in ProcessResult(stdout: "", stderr: "", status: 0) }
    let ftp = FTPFileSystem(host: "h", user: "me", password: "pw", secure: true, runner: runner)
    try await ftp.upload(local, to: URL(string: "ftps://h/My%20Docs/n.txt")!, replacing: true, progress: { _ in })
    let call = try #require(runner.calls.first)
    #expect(call.input.contains("upload-file = \"\(local.path)\""))
    #expect(call.input.contains("quote = \"-*DELE n.txt\"") && call.input.contains("quote = \"-RNTO n.txt\""))
    #expect(call.input.contains("url = \"ftps://h/My%20Docs/.n.txt.pane-part-") && !call.args.joined().contains("pw"))
    #expect(call.args.contains("--ssl-reqd") && call.args.contains("0"), "a transfer has no time limit")
    try await ftp.makeFolder(URL(string: "ftps://h/My%20Docs/New")!)
    #expect(runner.calls.last?.input.contains("quote = \"-MKD New\"") == true && runner.calls.last?.input.contains("url = \"ftps://h/My%20Docs/\"") == true)
}

struct FileStubTransport: S3Transport {
    let log: Collected2
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        log.add("\(request.httpMethod ?? "") \(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? "")")
        return (Data("<ListBucketResult><IsTruncated>false</IsTruncated></ListBucketResult>".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func upload(_ request: URLRequest, fromFile: URL, progress: @escaping ByteProgress) async throws -> (Data, HTTPURLResponse) {
        log.add("\(request.httpMethod ?? "") \(request.url?.path ?? "") \(request.value(forHTTPHeaderField: "x-amz-content-sha256") ?? "")")
        progress(2)
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func download(_ request: URLRequest, to file: URL, progress: @escaping ByteProgress) async throws -> HTTPURLResponse {
        try Data("from s3".utf8).write(to: file)
        progress(7)
        return HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }
}

@Test func s3UploadsFromDiskDownloadsToDiskAndDeletesAFolderDeeply() async throws {
    let log = Collected2()
    let s3 = S3FileSystem(endpoint: "s3.example.com", region: "us-east-1", credentials: .init(accessKey: "k", secretKey: "s"), transport: FileStubTransport(log: log))
    let local = scratchFolder().appending(path: "n.txt")
    try Data("hi".utf8).write(to: local)
    try await s3.upload(local, to: URL(string: "s3://s3.example.com/photos/trip/n.txt")!, replacing: false, progress: { _ in })
    #expect(log.values.first == "PUT /photos/trip/n.txt UNSIGNED-PAYLOAD")
    let saved = scratchFolder().appending(path: "out.txt")
    try await s3.download(URL(string: "s3://s3.example.com/photos/trip/n.txt")!, to: saved, progress: { _ in })
    #expect(try String(contentsOf: saved, encoding: .utf8) == "from s3")
    try await s3.makeFolder(URL(string: "s3://s3.example.com/photos/New")!)
    #expect(log.values.contains("PUT /photos/New/"))
    try await s3.remove(URL(string: "s3://s3.example.com/photos/trip")!)
    #expect(log.values.suffix(2) == ["DELETE /photos/trip", "DELETE /photos/trip/"])
    await #expect(throws: RemoteError.self) { try await s3.upload(local, to: URL(string: "s3://s3.example.com/photos")!, replacing: false, progress: { _ in }) }
}
