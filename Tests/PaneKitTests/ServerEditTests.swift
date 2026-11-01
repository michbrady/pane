import Foundation
import Testing
@testable import PaneKit

// MARK: Change files on a server (S-065)

@Test func theSameFileOperationsWorkOnAServer() async throws {
    let nas = InMemoryRemote(serverKey: "sftp://nas")
    nas.add(folder: "/Docs"); nas.add(file: "/Docs/old.txt", contents: Data("body".utf8)); nas.add(file: "/Docs/b.txt", contents: Data("b".utf8))
    let ops = FileOperations(nas)
    let (first, _) = try await ops.makeFolder(in: serverURL("/Docs"))
    let (second, _) = try await ops.makeFolder(in: serverURL("/Docs"))
    #expect(RemoteURL.name(of: first) == "New folder" && RemoteURL.name(of: second) == "New folder (2)")
    _ = try await ops.rename(serverURL("/Docs/old.txt"), to: "new name.txt")
    #expect(nas.data(at: "/Docs/new name.txt") == Data("body".utf8) && nas.data(at: "/Docs/old.txt") == nil)
    await #expect(throws: FileOperations.RenameError.taken) { _ = try await ops.rename(serverURL("/Docs/new name.txt"), to: "b.txt") }
    let failures = await ops.deleteImmediately([serverURL("/Docs/b.txt"), serverURL("/Docs/New folder")])
    #expect(failures.isEmpty && nas.data(at: "/Docs/b.txt") == nil && !nas.paths().contains("/Docs/New folder"))
}

struct ListingStub: S3Transport {
    let log: Collected2
    let keys: [String]
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        log.add("\(request.httpMethod ?? "") \(path) \(request.value(forHTTPHeaderField: "x-amz-copy-source") ?? "")".trimmingCharacters(in: .whitespaces))
        let body = request.httpMethod == "GET"
            ? "<ListBucketResult><IsTruncated>false</IsTruncated>" + keys.map { "<Contents><Key>\($0)</Key><Size>1</Size></Contents>" }.joined() + "</ListBucketResult>"
            : "<CopyObjectResult/>"
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Test func s3KnowsWhatIsThereAndRenamesByCopyingThenDeleting() async throws {
    let log = Collected2()
    let s3 = S3FileSystem(endpoint: "s3.example.com", region: "us-east-1", credentials: .init(accessKey: "k", secretKey: "s"),
                          transport: ListingStub(log: log, keys: ["real.txt"]))
    #expect(await s3.exists(URL(string: "s3://s3.example.com/photos/real.txt")!))
    #expect(await s3.exists(URL(string: "s3://s3.example.com/photos/ghost.txt")!) == false, "an empty listing is not proof that the name is there")
    let quiet = S3FileSystem(endpoint: "s3.example.com", region: "us-east-1", credentials: .init(accessKey: "k", secretKey: "s"),
                             transport: ListingStub(log: log, keys: []))
    try await quiet.move(URL(string: "s3://s3.example.com/photos/old%20name.txt")!, to: URL(string: "s3://s3.example.com/photos/new.txt")!)
    let moves = log.values.suffix(2)
    #expect(Array(moves) == ["PUT /photos/new.txt /photos/old%20name.txt", "DELETE /photos/old%20name.txt"])
}

@Test func sftpAndFtpRenameInPlace() async throws {
    let runner = ScriptedRunner { _, _, _ in ProcessResult(stdout: "", stderr: "", status: 0) }
    try await sftpSystem(runner).move(URL(string: "sftp://nas.local/My%20Docs/a")!, to: URL(string: "sftp://nas.local/My%20Docs/b")!)
    #expect(runner.calls.last?.input == "rename \"/My Docs/a\" \"/My Docs/b\"\n")
    let ftp = FTPFileSystem(host: "h", user: "me", password: "pw", secure: false, runner: runner)
    try await ftp.move(URL(string: "ftp://h/Docs/a.txt")!, to: URL(string: "ftp://h/Docs/b.txt")!)
    let config = try #require(runner.calls.last).input
    #expect(config.contains("quote = \"-RNFR a.txt\"") && config.contains("quote = \"-RNTO b.txt\"") && config.contains("url = \"ftp://h/Docs/\""))
    await #expect(throws: RemoteError.self) { try await ftp.move(URL(string: "ftp://h/Docs/a.txt")!, to: URL(string: "ftp://h/Other/a.txt")!) }
}

// MARK: Open and edit a file on a server (S-066)

func editSetup() -> (RemoteEdits, InMemoryRemote, URL) {
    let router = FileSystemRouter()
    let nas = InMemoryRemote(serverKey: "sftp://nas")
    router.register(nas)
    nas.add(folder: "/Docs"); nas.add(file: "/Docs/Notes.txt", contents: Data("first".utf8))
    let root = scratchFolder().appending(path: "edits")
    return (RemoteEdits(router: router, root: root), nas, root)
}

func save(_ text: String, to file: URL) throws {
    try Data(text.utf8).write(to: file)
    // A save a moment later: make sure the time moved even on a fast disk.
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
}

@Test func openingDownloadsATemporaryCopyThatSavesGoBackFrom() async throws {
    let (edits, nas, root) = editSetup()
    let local = try await edits.open(serverURL("/Docs/Notes.txt"), progress: { _ in })
    #expect(local.lastPathComponent == "Notes.txt" && local.path.hasPrefix(root.path))
    #expect(try String(contentsOf: local, encoding: .utf8) == "first")
    #expect(edits.changed().isEmpty, "nothing to send before a save")
    try save("second", to: local)
    let session = try #require(edits.changed().first)
    #expect(try await edits.sync(session.id) == .uploaded)
    #expect(nas.data(at: "/Docs/Notes.txt") == Data("second".utf8))
    #expect(edits.changed().isEmpty)
    let again = try await edits.sync(session.id)
    #expect(again == .unchanged)
    try save("third", to: local)
    let third = try await edits.sync(session.id)
    #expect(third == .uploaded && nas.data(at: "/Docs/Notes.txt") == Data("third".utf8), "later saves go back too")
}

@Test func aFileChangedOnTheServerIsNeverOverwrittenWithoutAsking() async throws {
    let (edits, nas, _) = editSetup()
    let local = try await edits.open(serverURL("/Docs/Notes.txt"), progress: { _ in })
    nas.add(file: "/Docs/Notes.txt", contents: Data("someone else was here".utf8))
    try save("mine", to: local)
    let session = try #require(edits.changed().first)
    #expect(try await edits.sync(session.id) == .serverChanged)
    #expect(nas.data(at: "/Docs/Notes.txt") == Data("someone else was here".utf8), "nothing was sent")
    edits.hold(session.id)
    #expect(edits.changed().isEmpty, "Not Now does not ask again until the next save")
    try save("mine, again", to: local)
    #expect(edits.changed().count == 1)
    #expect(try await edits.sync(session.id, replacing: true) == .uploaded)
    #expect(nas.data(at: "/Docs/Notes.txt") == Data("mine, again".utf8))
}

@Test func temporaryCopiesAreDeletedWhenPaneQuits() async throws {
    let (edits, _, root) = editSetup()
    _ = try await edits.open(serverURL("/Docs/Notes.txt"), progress: { _ in })
    #expect(FileManager.default.fileExists(atPath: root.path))
    edits.discardAll()
    #expect(!FileManager.default.fileExists(atPath: root.path) && edits.isEmpty)
}

@Test func aFailedDownloadLeavesNoTemporaryFolder() async throws {
    let (edits, nas, root) = editSetup()
    nas.add(file: "/Docs/big.bin", contents: Data(repeating: 1, count: 3000))
    nas.failTransfers(of: ["/Docs/big.bin"])
    await #expect(throws: RemoteError.connectionLost) { _ = try await edits.open(serverURL("/Docs/big.bin"), progress: { _ in }) }
    #expect(((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).isEmpty && edits.isEmpty)
}
