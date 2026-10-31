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

@Test func dragRulesFollowVolumeAndModifierKeys() {
    #expect(DropRules.mode(sameVolume: true, option: false, command: false) == .move)
    #expect(DropRules.mode(sameVolume: false, option: false, command: false) == .copy)
    #expect(DropRules.mode(sameVolume: true, option: true, command: false) == .copy)
    #expect(DropRules.mode(sameVolume: false, option: false, command: true) == .move)
    #expect(DropRules.mode(sameVolume: false, option: true, command: true) == .copy)
}

@Test func sameVolumeIsTrueInsideOneFolderTree() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-vol-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appending(path: "a"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appending(path: "b"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(DropRules.sameVolume([root.appending(path: "a")], as: root.appending(path: "b")))
    #expect(!DropRules.sameVolume([root.appending(path: "missing")], as: root.appending(path: "b")))
}

private func item(_ name: String, folder: Bool = false, size: Int64? = nil, modified: Double? = nil, kind: String = "File") -> FolderItem {
    FolderItem(url: URL(fileURLWithPath: "/x/\(name)"), name: name, isFolder: folder, size: folder ? nil : size,
               modified: modified.map { Date(timeIntervalSince1970: $0) }, kind: folder ? "File folder" : kind)
}

@Test func sortByNameIsNaturalAndKeepsFoldersFirst() {
    let items = [item("file10.txt"), item("Zed", folder: true), item("file2.txt"), item("alpha", folder: true)]
    let up = FolderSorter.sorted(items, key: .name, ascending: true, foldersFirst: true).map(\.name)
    #expect(up == ["alpha", "Zed", "file2.txt", "file10.txt"])
    let down = FolderSorter.sorted(items, key: .name, ascending: false, foldersFirst: true).map(\.name)
    #expect(down == ["Zed", "alpha", "file10.txt", "file2.txt"])
}

@Test func sortBySizeUsesBytesNotText() {
    let items = [item("a", size: 900), item("b", size: 1_500_000), item("c", size: 20_000)]
    #expect(FolderSorter.sorted(items, key: .size, ascending: true, foldersFirst: true).map(\.name) == ["a", "c", "b"])
    #expect(FolderSorter.sorted(items, key: .size, ascending: false, foldersFirst: true).map(\.name) == ["b", "c", "a"])
}

@Test func foldersFirstCanBeTurnedOff() {
    let items = [item("b.txt", size: 5), item("A", folder: true), item("c.txt", size: 1)]
    #expect(FolderSorter.sorted(items, key: .name, ascending: true, foldersFirst: false).map(\.name) == ["A", "b.txt", "c.txt"])
    #expect(FolderSorter.sorted(items, key: .size, ascending: false, foldersFirst: false).map(\.name) == ["b.txt", "c.txt", "A"])
}

@Test func sortByDateAndKindFallBackToName() {
    let items = [item("b", modified: 100, kind: "PDF"), item("a", modified: 100, kind: "PDF"), item("c", modified: 50, kind: "Text")]
    #expect(FolderSorter.sorted(items, key: .modified, ascending: true, foldersFirst: true).map(\.name) == ["c", "a", "b"])
    #expect(FolderSorter.sorted(items, key: .kind, ascending: true, foldersFirst: true).map(\.name) == ["a", "b", "c"])
}

@Test func extensionsCanBeHiddenFromTheDisplayName() {
    #expect(item("Budget 2026.xlsx").displayName(showExtensions: false) == "Budget 2026")
    #expect(item("Budget 2026.xlsx").displayName(showExtensions: true) == "Budget 2026.xlsx")
    #expect(item("report.final.pdf").displayName(showExtensions: false) == "report.final")
    #expect(item("v1.2", folder: true).displayName(showExtensions: false) == "v1.2")
    #expect(item(".gitignore").displayName(showExtensions: false) == ".gitignore")
    #expect(item("README").displayName(showExtensions: false) == "README")
}

@Test func pinsKeepOrderAndIgnoreDuplicates() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-pins-\(UUID().uuidString)")
    for name in ["a", "b", "c"] { try FileManager.default.createDirectory(at: root.appending(path: name), withIntermediateDirectories: true) }
    defer { try? FileManager.default.removeItem(at: root) }
    var pins = PinStore(saved: nil, defaults: [root.appending(path: "a")])
    pins.pin(root.appending(path: "b"))
    pins.pin(root.appending(path: "b"))
    pins.pin(root.appending(path: "c"), at: 0)
    #expect(pins.urls.map(\.lastPathComponent) == ["c", "a", "b"])
    pins.unpin(root.appending(path: "a"))
    #expect(pins.urls.map(\.lastPathComponent) == ["c", "b"])
    #expect(pins.contains(root.appending(path: "c")) && !pins.contains(root.appending(path: "a")))
}

@Test func aPinnedFolderStillResolvesAfterItIsRenamed() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-rename-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appending(path: "Projects"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var pins = PinStore(saved: nil, defaults: [])
    pins.pin(root.appending(path: "Projects"))
    try FileManager.default.moveItem(at: root.appending(path: "Projects"), to: root.appending(path: "Work"))
    #expect(pins.urls.map(\.lastPathComponent) == ["Work"])
    let reloaded = PinStore(saved: pins.bookmarks, defaults: [])
    #expect(reloaded.urls.map(\.lastPathComponent) == ["Work"])
}

@Test func filesAndMissingFoldersCannotBePinned() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-pinfile-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("x".utf8).write(to: root.appending(path: "file.txt"))
    var pins = PinStore(saved: nil, defaults: [])
    pins.pin(root.appending(path: "file.txt"))
    pins.pin(root.appending(path: "missing"))
    #expect(pins.urls.isEmpty)
}

@Test func listingReadsCreatedDateAndTags() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-tags-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "tagged.txt")
    try Data("x".utf8).write(to: file)
    var values = URLResourceValues()
    values.tagNames = ["Work", "Red"]
    var mutable = file
    try mutable.setResourceValues(values)
    let listed = try FolderLister.list(root)
    #expect(listed.first?.created != nil)
    #expect(Set(listed.first?.tags ?? []) == ["Work", "Red"])
}

@Test func sortByCreatedDateFallsBackToName() {
    let a = FolderItem(url: URL(fileURLWithPath: "/x/a"), name: "a", isFolder: false, size: 1, modified: nil, kind: "File", created: Date(timeIntervalSince1970: 200))
    let b = FolderItem(url: URL(fileURLWithPath: "/x/b"), name: "b", isFolder: false, size: 1, modified: nil, kind: "File", created: Date(timeIntervalSince1970: 100))
    #expect(FolderSorter.sorted([a, b], key: .created, ascending: true, foldersFirst: true).map(\.name) == ["b", "a"])
}

@Test func statusBarSaysItemsAndSelection() {
    #expect(SelectionSummary.text(itemCount: 12, selected: []) == "12 items")
    #expect(SelectionSummary.text(itemCount: 1, selected: []) == "1 item")
    #expect(SelectionSummary.text(itemCount: 0, selected: []) == "0 items")
    let three = [item("a", size: 1_000_000), item("b", size: 2_000_000), item("c", size: 1_100_000)]
    #expect(SelectionSummary.text(itemCount: 12, selected: three) == "3 items selected  4.1 MB")
    #expect(SelectionSummary.text(itemCount: 12, selected: [three[0]]) == "1 item selected  1 MB")
    #expect(SelectionSummary.text(itemCount: 5, selected: [item("Folder", folder: true)]) == "1 item selected")
}

@Test func permissionsReadLikeLs() {
    #expect(ItemProperties.permissionText(0o644) == "rw-r--r--")
    #expect(ItemProperties.permissionText(0o755) == "rwxr-xr-x")
    #expect(ItemProperties.permissionText(0o000) == "---------")
}

@Test func propertiesOfAFileAndAFolder() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-props-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appending(path: "sub"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(count: 5000).write(to: root.appending(path: "sub/a.bin"))
    try Data(count: 300).write(to: root.appending(path: "b.bin"))
    let file = try #require(ItemProperties.read(root.appending(path: "sub/a.bin")))
    #expect(file.name == "a.bin" && file.size == 5000 && !file.isFolder)
    #expect((file.sizeOnDisk ?? 0) >= 5000)
    #expect(file.location.hasSuffix("/sub") && file.created != nil && file.modified != nil)
    let folder = try #require(ItemProperties.read(root))
    #expect(folder.isFolder && folder.size == nil && folder.kind == "File folder")
    let total = FolderTotal.measure(root)
    #expect(total.bytes == 5300 && total.files == 2 && total.folders == 1)
}

@Test func aCancelledFolderTotalStopsEarly() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-cancel-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for i in 0..<20 { try Data(count: 10).write(to: root.appending(path: "f\(i)")) }
    #expect(FolderTotal.measure(root, isCancelled: { true }).files == 0)
}

@Test func aFolderTotalRunsInTheBackground() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-bg-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(count: 123).write(to: root.appending(path: "x"))
    let total = await FolderTotal.measureInBackground(root)
    #expect(total.bytes == 123)
}

@Test func tagsAreAddedAndRemovedThroughResourceValues() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-tagedit-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let a = root.appending(path: "a.txt"), b = root.appending(path: "b.txt")
    try Data("x".utf8).write(to: a)
    try Data("x".utf8).write(to: b)
    #expect(TagEditor.apply("Red", to: [a, b], add: true).isEmpty)
    #expect(TagEditor.tags(of: a) == ["Red"] && TagEditor.tags(of: b) == ["Red"])
    TagEditor.apply("Red", to: [a], add: true)
    #expect(TagEditor.tags(of: a) == ["Red"])
    TagEditor.apply("Work", to: [a], add: true)
    #expect(Set(TagEditor.tags(of: a)) == ["Red", "Work"])
    TagEditor.apply("Red", to: [a, b], add: false)
    #expect(TagEditor.tags(of: a) == ["Work"] && TagEditor.tags(of: b).isEmpty)
    TagEditor.removeAll(from: [a, b])
    #expect(TagEditor.tags(of: a).isEmpty)
    #expect(TagEditor.standard.count == 7)
}

@Test func previewKindsFollowTheFileType() {
    #expect(PreviewKind.kind(for: URL(fileURLWithPath: "/x/photo.JPG")) == .image)
    #expect(PreviewKind.kind(for: URL(fileURLWithPath: "/x/a.png")) == .image)
    #expect(PreviewKind.kind(for: URL(fileURLWithPath: "/x/doc.pdf")) == .pdf)
    #expect(PreviewKind.kind(for: URL(fileURLWithPath: "/x/notes.txt")) == .text)
    #expect(PreviewKind.kind(for: URL(fileURLWithPath: "/x/readme.md")) == .text)
    #expect(PreviewKind.kind(for: URL(fileURLWithPath: "/x/main.swift")) == .text)
    #expect(PreviewKind.kind(for: URL(fileURLWithPath: "/x/data.json")) == .text)
    #expect(PreviewKind.kind(for: URL(fileURLWithPath: "/x/archive.zip")) == .other)
    #expect(PreviewKind.kind(for: URL(fileURLWithPath: "/x/noextension")) == .other)
}

@Test func textPreviewStopsAtTheLimit() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "pane-text-\(UUID().uuidString).txt")
    try Data(String(repeating: "abc ", count: 5000).utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(PreviewKind.textPreview(of: file, limit: 100)?.count == 100)
    #expect(PreviewKind.textPreview(of: file)?.count == 20_000)
    #expect(PreviewKind.textPreview(of: file.appending(path: "missing")) == nil)
}

private struct FakeSpotlight: SpotlightSearching {
    let urls: [URL]
    func search(_ text: String, in folder: URL) async -> [URL] { urls }
}

private func searchTree() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-search-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: root.appending(path: "Work/Deep"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appending(path: ".hiddenfolder"), withIntermediateDirectories: true)
    for path in ["Budget 2026.xlsx", "Work/Budget notes.txt", "Work/Deep/old BUDGET.md", "Work/Roadmap.key",
                 ".hiddenfolder/budget secret.txt", "Café.txt"] {
        try Data("x".utf8).write(to: root.appending(path: path))
    }
    return root
}

private func collect(_ text: String, in root: URL, spotlight: SpotlightSearching? = nil, showHidden: Bool = false) async -> [String] {
    var names: [String] = []
    for await batch in FileSearch.results(for: text, in: root, spotlight: spotlight, showHidden: showHidden) { names += batch.map(\.name) }
    return names.sorted()
}

@Test func searchFindsNamesBelowTheFolderIgnoringCase() async throws {
    let root = try searchTree()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(await collect("budget", in: root) == ["Budget 2026.xlsx", "Budget notes.txt", "old BUDGET.md"])
    #expect(await collect("roadmap", in: root) == ["Roadmap.key"])
    #expect(await collect("nothing here", in: root).isEmpty)
}

@Test func searchIgnoresAccentsAndSkipsHiddenItemsUnlessAsked() async throws {
    let root = try searchTree()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(await collect("cafe", in: root) == ["Café.txt"])
    #expect(await collect("secret", in: root).isEmpty)
    #expect(await collect("secret", in: root, showHidden: true) == ["budget secret.txt"])
}

@Test func searchPrefersSpotlightWhenItAnswers() async throws {
    let root = try searchTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let spotlight = FakeSpotlight(urls: [root.appending(path: "Work/Roadmap.key")])
    #expect(await collect("budget", in: root, spotlight: spotlight) == ["Roadmap.key"])
}

@Test func searchFallsBackToAScanWhenSpotlightHasNothing() async throws {
    let root = try searchTree()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(await collect("roadmap", in: root, spotlight: FakeSpotlight(urls: [])) == ["Roadmap.key"])
}

@Test func theMatchRuleIgnoresCaseAndAccents() {
    #expect(FileSearch.matches("Résumé Final.PDF", "resume"))
    #expect(FileSearch.matches("notes.txt", "NOTES"))
    #expect(!FileSearch.matches("notes.txt", "memo"))
}

private actor Counter {
    var value = 0
    func bump() { value += 1 }
}
