import Foundation
import Testing
@testable import PaneKit

private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }
private let keepAsking: FileOperations.Resolver = { _ in ConflictDecision(choice: .skip) }

private func makeFS() -> InMemoryFileSystem {
    let fs = InMemoryFileSystem()
    fs.add(folder: "/src"); fs.add(folder: "/dst"); fs.add(folder: "/src/Photos")
    fs.add(file: "/src/Photos/a.jpg"); fs.add(file: "/src/a.txt", size: 10); fs.add(file: "/src/b.txt", size: 20)
    return fs
}

@Test func copyKeepsTheOriginalAndCopiesFolders() async {
    let fs = makeFS()
    let result = await FileOperations(fs).paste([url("/src/a.txt"), url("/src/Photos")], into: url("/dst"), mode: .copy, resolve: keepAsking)
    #expect(result.failures.isEmpty)
    #expect(fs.paths().contains("/dst/a.txt") && fs.paths().contains("/dst/Photos/a.jpg"))
    #expect(fs.paths().contains("/src/a.txt"))
    #expect(result.record.name == "Copy 2 Items")
}

@Test func moveRemovesTheOriginal() async {
    let fs = makeFS()
    _ = await FileOperations(fs).paste([url("/src/a.txt")], into: url("/dst"), mode: .move, resolve: keepAsking)
    #expect(fs.paths().contains("/dst/a.txt"))
    #expect(!fs.paths().contains("/src/a.txt"))
}

@Test func pastingIntoTheSameFolderMakesACopyAndMoveDoesNothing() async {
    let fs = makeFS()
    let ops = FileOperations(fs)
    _ = await ops.paste([url("/src/a.txt")], into: url("/src"), mode: .copy, resolve: keepAsking)
    _ = await ops.paste([url("/src/a.txt")], into: url("/src"), mode: .copy, resolve: keepAsking)
    #expect(fs.paths().contains("/src/a - Copy.txt") && fs.paths().contains("/src/a - Copy (2).txt"))
    let moved = await ops.paste([url("/src/b.txt")], into: url("/src"), mode: .move, resolve: keepAsking)
    #expect(moved.record.isEmpty && fs.paths().contains("/src/b.txt"))
}

@Test func aFolderCannotGoInsideItself() async {
    let fs = makeFS()
    let result = await FileOperations(fs).paste([url("/src")], into: url("/src/Photos"), mode: .copy, resolve: keepAsking)
    #expect(result.failures.count == 1 && result.record.isEmpty)
}

@Test func skipLeavesBothFilesAlone() async {
    let fs = makeFS(); fs.add(file: "/dst/a.txt", size: 99)
    let result = await FileOperations(fs).paste([url("/src/a.txt")], into: url("/dst"), mode: .copy, resolve: { _ in ConflictDecision(choice: .skip) })
    #expect(result.skipped == [url("/src/a.txt")] && result.record.isEmpty)
}

@Test func doThisForAllAsksOnce() async {
    let fs = makeFS(); fs.add(file: "/dst/a.txt"); fs.add(file: "/dst/b.txt")
    let asked = Counter()
    let result = await FileOperations(fs).paste([url("/src/a.txt"), url("/src/b.txt")], into: url("/dst"), mode: .copy, resolve: { _ in
        await asked.bump(); return ConflictDecision(choice: .skip, applyToAll: true)
    })
    #expect(await asked.value == 1 && result.skipped.count == 2)
}

@Test func replaceTrashesTheOldItemAndUndoPutsItBack() async throws {
    let fs = makeFS(); fs.add(file: "/dst/a.txt", size: 99)
    let ops = FileOperations(fs)
    let result = await ops.paste([url("/src/a.txt")], into: url("/dst"), mode: .copy, resolve: { _ in ConflictDecision(choice: .replace) })
    #expect(result.failures.isEmpty)
    #expect(fs.paths().contains("/.Trash/a.txt"))
    try await ops.undo(result.record)
    let items = try await fs.list(url("/dst"))
    #expect(items.first { $0.name == "a.txt" }?.size == 99)
}

@Test func aFailedReplaceKeepsTheOriginal() async {
    let fs = makeFS(); fs.add(file: "/dst/a.txt", size: 99)
    fs.failingPaths = ["/src/a.txt"]
    let result = await FileOperations(fs).paste([url("/src/a.txt")], into: url("/dst"), mode: .copy, resolve: { _ in ConflictDecision(choice: .replace) })
    #expect(result.failures.count == 1)
    #expect(fs.paths().contains("/dst/a.txt") && !fs.paths().contains("/.Trash/a.txt"))
}

@Test func keepBothAddsANumber() async {
    let fs = makeFS(); fs.add(file: "/dst/a.txt")
    _ = await FileOperations(fs).paste([url("/src/a.txt")], into: url("/dst"), mode: .copy, resolve: { _ in ConflictDecision(choice: .keepBoth) })
    #expect(fs.paths().contains("/dst/a (2).txt"))
}

@Test func undoAndRedoOfAMove() async throws {
    let fs = makeFS()
    let ops = FileOperations(fs)
    let result = await ops.paste([url("/src/a.txt")], into: url("/dst"), mode: .move, resolve: keepAsking)
    try await ops.undo(result.record)
    #expect(fs.paths().contains("/src/a.txt") && !fs.paths().contains("/dst/a.txt"))
    _ = try await ops.redo(result.record)
    #expect(fs.paths().contains("/dst/a.txt") && !fs.paths().contains("/src/a.txt"))
}

@Test func trashUndoRestoresThePath() async throws {
    let fs = makeFS()
    let ops = FileOperations(fs)
    let result = await ops.trash([url("/src/a.txt")])
    #expect(!fs.paths().contains("/src/a.txt") && fs.paths().contains("/.Trash/a.txt"))
    try await ops.undo(result.record)
    #expect(fs.paths().contains("/src/a.txt"))
    let again = try await ops.redo(result.record)
    #expect(!fs.paths().contains("/src/a.txt"))
    try await ops.undo(again)
    #expect(fs.paths().contains("/src/a.txt"))
}

@Test func newFolderNamesCountUp() async throws {
    let fs = makeFS()
    let ops = FileOperations(fs)
    let (first, _) = try await ops.makeFolder(in: url("/dst"))
    let (second, _) = try await ops.makeFolder(in: url("/dst"))
    #expect(first.lastPathComponent == "New folder" && second.lastPathComponent == "New folder (2)")
}

@Test func renameRejectsTakenEmptyAndSlashNames() async throws {
    let fs = makeFS()
    let ops = FileOperations(fs)
    await #expect(throws: FileOperations.RenameError.taken) { try await ops.rename(url("/src/a.txt"), to: "b.txt") }
    await #expect(throws: FileOperations.RenameError.empty) { try await ops.rename(url("/src/a.txt"), to: "  ") }
    await #expect(throws: FileOperations.RenameError.hasSlash) { try await ops.rename(url("/src/a.txt"), to: "x/y") }
    let record = try await ops.rename(url("/src/a.txt"), to: "c.txt")
    #expect(fs.paths().contains("/src/c.txt"))
    try await ops.undo(record)
    #expect(fs.paths().contains("/src/a.txt"))
}

@Test func localFileSystemCopiesAndMoves() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-ops-\(UUID().uuidString)")
    let src = root.appending(path: "src"), dst = root.appending(path: "dst")
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("hello".utf8).write(to: src.appending(path: "a.txt"))
    let ops = FileOperations(LocalFileSystem())
    let copied = await ops.paste([src.appending(path: "a.txt")], into: dst, mode: .copy, resolve: keepAsking)
    #expect(copied.failures.isEmpty)
    #expect(try String(contentsOf: dst.appending(path: "a.txt"), encoding: .utf8) == "hello")
    let moved = await ops.paste([src.appending(path: "a.txt")], into: dst, mode: .move, resolve: { _ in ConflictDecision(choice: .replace) })
    #expect(moved.failures.isEmpty && !FileManager.default.fileExists(atPath: src.appending(path: "a.txt").path))
}

@Test func copyKeepsTheModifiedDateAndFolderContents() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-date-\(UUID().uuidString)")
    let folder = root.appending(path: "src/Docs"), dst = root.appending(path: "dst")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = folder.appending(path: "a.txt")
    try Data("x".utf8).write(to: file)
    let old = Date(timeIntervalSince1970: 1_000_000_000)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
    let result = await FileOperations(LocalFileSystem()).paste([folder], into: dst, mode: .copy, resolve: keepAsking)
    #expect(result.failures.isEmpty)
    let copied = dst.appending(path: "Docs/a.txt")
    let date = try copied.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    #expect(date == old)
}

@Test func renameSelectsTheNameButNotTheExtension() {
    #expect(NameMaker.baseNameLength("report.final.pdf", isFolder: false) == 12)
    #expect(NameMaker.baseNameLength("Photos", isFolder: true) == 6)
    #expect(NameMaker.baseNameLength("v1.2", isFolder: true) == 4)
    #expect(NameMaker.baseNameLength(".gitignore", isFolder: false) == 10)
    #expect(NameMaker.baseNameLength("README", isFolder: false) == 6)
}

private actor Counter {
    var value = 0
    func bump() { value += 1 }
}
