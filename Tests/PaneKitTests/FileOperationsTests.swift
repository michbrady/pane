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

@Test func openInTerminalPicksTheRightFolder() {
    let current = URL(fileURLWithPath: "/Users/me/Documents")
    let folder = item("Work", folder: true)
    let file = item("notes.txt", size: 1)
    #expect(OpenInTerminal.folder(selected: [], current: current) == current)
    #expect(OpenInTerminal.folder(selected: [folder], current: current) == folder.url)
    #expect(OpenInTerminal.folder(selected: [file], current: current).path == "/x")
    #expect(OpenInTerminal.folder(selected: [folder, file], current: current) == current)
}

@Test func theFullDiskAccessGuideShowsOnceAndOnlyWhenNeeded() {
    #expect(FullDiskAccessGuide.shouldShow(granted: false, shownBefore: false))
    #expect(!FullDiskAccessGuide.shouldShow(granted: true, shownBefore: false))
    #expect(!FullDiskAccessGuide.shouldShow(granted: false, shownBefore: true))
    #expect(!FullDiskAccessGuide.shouldShow(granted: true, shownBefore: true))
    #expect(FullDiskAccessGuide.reason.hasSuffix("about each one."))
    #expect(!FullDiskAccessGuide.reason.contains("\n"))
}

@Test func theDefaultShortcutIsControlOptionE() {
    #expect(Shortcut.default.displayText == "⌃⌥E")
    #expect(Shortcut.default.isValid)
}

@Test func aGlobalShortcutNeedsACommandOptionOrControlKey() {
    #expect(!Shortcut(keyCode: 14, modifiers: 0).isValid)
    #expect(!Shortcut(keyCode: 14, modifiers: Shortcut.shift).isValid)
    #expect(Shortcut(keyCode: 14, modifiers: Shortcut.command | Shortcut.shift).isValid)
    #expect(!Shortcut(keyCode: 9999, modifiers: Shortcut.command).isValid)
}

@Test func shortcutsReadInTheMacOrderAndSurviveSaving() throws {
    let shortcut = Shortcut(keyCode: 1, modifiers: Shortcut.command | Shortcut.shift | Shortcut.option | Shortcut.control)
    #expect(shortcut.displayText == "⌃⌥⇧⌘S")
    let decoded = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(shortcut))
    #expect(decoded == shortcut)
}

@Test func volumesSplitIntoDrivesAndNetworkShares() {
    let root = VolumeInfo(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", isLocal: true, isEjectable: false)
    let backup = VolumeInfo(url: URL(fileURLWithPath: "/Volumes/Backup"), name: "Backup", isLocal: true, isEjectable: true)
    let archive = VolumeInfo(url: URL(fileURLWithPath: "/Volumes/Archive"), name: "Archive", isLocal: true, isEjectable: true)
    let nas = VolumeInfo(url: URL(fileURLWithPath: "/Volumes/photos"), name: "photos", isLocal: false, isEjectable: true)
    let split = VolumeSections.split([nas, backup, root, archive])
    #expect(split.drives.map(\.name) == ["Macintosh HD", "Archive", "Backup"])
    #expect(split.network.map(\.name) == ["photos"])
}

@Test func networkFoldersArePolledAndLocalOnesAreNot() {
    #expect(PollPolicy.interval(isLocal: false) == 10)
    #expect(PollPolicy.interval(isLocal: true) == nil)
    #expect(!VolumeInfo.isNetwork(FileManager.default.temporaryDirectory))
}

@Test func mountedVolumesIncludeTheStartupDisk() {
    let volumes = VolumeInfo.mounted()
    #expect(volumes.contains { $0.url.path == "/" && $0.isLocal })
    #expect(!volumes.contains { $0.url.path.hasPrefix("/System/Volumes") })
}

@Test func cloudProvidersGetTheNamesPeopleKnow() {
    #expect(CloudLocations.displayName(forFolderName: "Dropbox") == "Dropbox")
    #expect(CloudLocations.displayName(forFolderName: "GoogleDrive-me@example.com") == "Google Drive (me@example.com)")
    #expect(CloudLocations.displayName(forFolderName: "OneDrive-Work") == "OneDrive (Work)")
    #expect(CloudLocations.displayName(forFolderName: "OneDrive") == "OneDrive")
    #expect(CloudLocations.displayName(forFolderName: "Box-Box") == "Box")
    #expect(CloudLocations.displayName(forFolderName: "SomethingElse") == "SomethingElse")
}

@Test func cloudFoldersAreFoundUnderTheHomeFolder() throws {
    let home = FileManager.default.temporaryDirectory.appending(path: "pane-cloud-\(UUID().uuidString)")
    let fm = FileManager.default
    for path in ["Library/Mobile Documents/com~apple~CloudDocs", "Library/CloudStorage/Dropbox", "Library/CloudStorage/GoogleDrive-me@example.com", "Library/CloudStorage/.hidden"] {
        try fm.createDirectory(at: home.appending(path: path), withIntermediateDirectories: true)
    }
    try Data("x".utf8).write(to: home.appending(path: "Library/CloudStorage/loose-file.txt"))
    defer { try? fm.removeItem(at: home) }
    let found = CloudLocations.list(home: home)
    #expect(found.map(\.name) == ["iCloud Drive", "Dropbox", "Google Drive (me@example.com)"])
    #expect(CloudLocations.list(home: home.appending(path: "nowhere")).isEmpty)
}

@Test func onlineOnlyFilesAreRecognizedByTheDatalessFlag() {
    #expect(OnlineStatus.isOnlineOnly(flags: 0x4000_0000))
    #expect(OnlineStatus.isOnlineOnly(flags: 0x4000_0020))
    #expect(!OnlineStatus.isOnlineOnly(flags: 0x20))
    #expect(!OnlineStatus.isOnlineOnly(FileManager.default.temporaryDirectory))
}

@Test func oldICloudStubsAreShownUnderTheRealNameAndSize() throws {
    #expect(OnlineStatus.realName(ofPlaceholder: ".Report.pdf.icloud") == "Report.pdf")
    #expect(OnlineStatus.realName(ofPlaceholder: ".Notes.icloud") == "Notes")
    #expect(OnlineStatus.realName(ofPlaceholder: "Report.pdf") == nil)
    #expect(OnlineStatus.realName(ofPlaceholder: ".gitignore") == nil)
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-stub-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let plist = try PropertyListSerialization.data(fromPropertyList: ["NSURLFileSizeKey": 123_456, "NSURLNameKey": "Report.pdf"], format: .binary, options: 0)
    try plist.write(to: root.appending(path: ".Report.pdf.icloud"))
    try Data("x".utf8).write(to: root.appending(path: "local.txt"))
    try Data("x".utf8).write(to: root.appending(path: ".dotfile"))
    let listed = try FolderLister.list(root)
    #expect(listed.map(\.name) == ["local.txt", "Report.pdf"])
    let stub = try #require(listed.first { $0.name == "Report.pdf" })
    #expect(stub.isOnlineOnly && stub.size == 123_456 && stub.kind == "PDF document")
    #expect(!listed.contains { $0.name.hasSuffix(".icloud") })
}

@Test func theStatusBarCountsOnlineOnlyItems() {
    #expect(SelectionSummary.text(itemCount: 12, selected: [], onlineOnly: 3) == "12 items  ·  3 online only")
    #expect(SelectionSummary.text(itemCount: 12, selected: [], onlineOnly: 0) == "12 items")
    #expect(SelectionSummary.text(itemCount: 4, selected: [item("a", size: 1_000_000)], onlineOnly: 1) == "1 item selected  1 MB  ·  1 online only")
}

@Test func materializingALocalFileJustWorks() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "pane-mat-\(UUID().uuidString).txt")
    try Data("hello".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    try await CloudDownload.materialize(file)
}

@Test func anSMBAddressNeedsTheSMBScheme() {
    #expect(SMBAddress.parse("") == .failure(.empty))
    #expect(SMBAddress.parse("   ") == .failure(.empty))
    #expect(SMBAddress.parse("nas/photos") == .failure(.notSMB))
    #expect(SMBAddress.parse("http://nas/photos") == .failure(.notSMB))
    #expect(SMBAddress.parse("smb://") == .failure(.noHost))
    #expect(SMBAddress.parse("smb:///photos") == .failure(.noHost))
}

@Test func anSMBAddressSplitsIntoHostAndShare() throws {
    let address = try SMBAddress.parse("  SMB://nas.local/photos/2026 ").get()
    #expect(address.host == "nas.local" && address.path == ["photos", "2026"] && address.user == nil)
    #expect(address.url.absoluteString == "smb://nas.local/photos/2026")
    #expect(address.displayText == "smb://nas.local/photos/2026")
    let hostOnly = try SMBAddress.parse("smb://nas").get()
    #expect(hostOnly.path.isEmpty && hostOnly.url.absoluteString == "smb://nas")
}

@Test func spacesAndSpecialCharactersAreEncoded() throws {
    let spaced = try SMBAddress.parse("smb://nas/My Photos/Summer #1").get()
    #expect(spaced.path == ["My Photos", "Summer #1"])
    #expect(spaced.url.absoluteString == "smb://nas/My%20Photos/Summer%20%231")
    let encoded = try SMBAddress.parse("smb://nas/My%20Photos").get()
    #expect(encoded.path == ["My Photos"] && encoded.url.absoluteString == "smb://nas/My%20Photos")
    let named = try SMBAddress.parse("smb://me@nas/share").get()
    #expect(named.user == "me" && named.host == "nas" && named.url.absoluteString == "smb://me@nas/share")
}

@Test func recentServersKeepTheNewestFirstWithoutRepeats() {
    var recent = RecentServers()
    recent.add("smb://nas/photos")
    recent.add("smb://backup/files")
    recent.add("SMB://NAS/photos")
    #expect(recent.items == ["SMB://NAS/photos", "smb://backup/files"])
    for n in 0..<10 { recent.add("smb://host\(n)/share") }
    #expect(recent.items.count == RecentServers.limit && recent.items.first == "smb://host9/share")
    recent.clear()
    #expect(recent.items.isEmpty)
}

@Test func connectionErrorsAreExplainedInPlainWords() {
    #expect(ConnectionError.message(forCode: 80) == "The name or password was not accepted.")
    #expect(ConnectionError.message(forCode: 2).contains("no share with that name"))
    #expect(ConnectionError.message(forCode: 60).contains("did not answer"))
    #expect(ConnectionError.message(forCode: 17) == "That share is already connected.")
    #expect(ConnectionError.message(forCode: 999) == "Unable to connect (error 999).")
}

@MainActor @Test func pickingPaneAsTheFolderAppRemembersWhatWasThere() async {
    let system = InMemoryFolderHandlerSystem(viewer: "com.cocoatech.PathFinder", handler: "com.apple.finder")
    var state = FolderHandlerState()
    await FolderHandlerSwitch.turnOn(system, as: "com.michaelbrady.pane", state: &state)
    #expect(system.viewer == "com.michaelbrady.pane" && system.handler == "com.michaelbrady.pane")
    #expect(state.isOn && state.previousFileViewer == "com.cocoatech.PathFinder" && state.previousFolderHandler == "com.apple.finder")
}

@MainActor @Test func turningItOffPutsTheEarlierAppsBack() async {
    let system = InMemoryFolderHandlerSystem(viewer: "com.cocoatech.PathFinder", handler: "com.apple.finder")
    var state = FolderHandlerState()
    await FolderHandlerSwitch.turnOn(system, as: "com.michaelbrady.pane", state: &state)
    await FolderHandlerSwitch.turnOff(system, state: &state)
    #expect(system.viewer == "com.cocoatech.PathFinder" && system.handler == "com.apple.finder")
    #expect(state == FolderHandlerState())
}

@MainActor @Test func turningItOnTwiceKeepsTheFirstMemory() async {
    let system = InMemoryFolderHandlerSystem(viewer: nil, handler: "com.apple.finder")
    var state = FolderHandlerState()
    await FolderHandlerSwitch.turnOn(system, as: "com.michaelbrady.pane", state: &state)
    await FolderHandlerSwitch.turnOn(system, as: "com.michaelbrady.pane", state: &state)
    #expect(state.previousFileViewer == nil && state.previousFolderHandler == "com.apple.finder")
    await FolderHandlerSwitch.turnOff(system, state: &state)
    #expect(system.viewer == nil && system.handler == "com.apple.finder")
}

@MainActor @Test func turningOffWhenNeverOnChangesNothing() async {
    let system = InMemoryFolderHandlerSystem(viewer: "x.y.z", handler: "a.b.c")
    var state = FolderHandlerState()
    await FolderHandlerSwitch.turnOff(system, state: &state)
    #expect(system.viewer == "x.y.z" && system.handler == "a.b.c")
}

@MainActor @Test func withNothingRememberedOffFallsBackToFinder() async {
    let system = InMemoryFolderHandlerSystem(viewer: nil, handler: nil)
    var state = FolderHandlerState()
    await FolderHandlerSwitch.turnOn(system, as: "com.michaelbrady.pane", state: &state)
    await FolderHandlerSwitch.turnOff(system, state: &state)
    #expect(system.viewer == nil && system.handler == FolderHandlerSwitch.finder)
}

@Test func theRememberedStateSurvivesSaving() throws {
    var state = FolderHandlerState()
    state.isOn = true
    state.previousFileViewer = "com.cocoatech.PathFinder"
    let decoded = try JSONDecoder().decode(FolderHandlerState.self, from: JSONEncoder().encode(state))
    #expect(decoded == state)
}

@Test func remoteURLsAreRecognizedAndMadeTidy() {
    #expect(RemoteURL.isRemote(URL(string: "sftp://nas/files")!))
    #expect(RemoteURL.isRemote(URL(string: "S3://bucket/key")!))
    #expect(!RemoteURL.isRemote(URL(fileURLWithPath: "/Users/me")))
    #expect(!RemoteURL.isRemote(URL(string: "https://example.com")!))
    #expect(RemoteURL.make(scheme: "SFTP", host: "nas.local", port: 2222, user: "me", path: "Documents/2026").absoluteString == "sftp://me@nas.local:2222/Documents/2026")
    #expect(RemoteURL.make(scheme: "ftp", host: "host").absoluteString == "ftp://host/")
    #expect(RemoteURL.canonical(URL(string: "SFTP://NAS/a/./b/../c/")!).absoluteString == "sftp://nas/a/c")
    #expect(RemoteURL.canonical(URL(string: "sftp://nas")!).absoluteString == "sftp://nas/")
}

@Test func aRemoteFolderWalksUpToTheTopOfTheServer() {
    let url = URL(string: "sftp://nas/Documents/Work/2026")!
    #expect(RemoteURL.chain(for: url).map(\.absoluteString) == ["sftp://nas/", "sftp://nas/Documents", "sftp://nas/Documents/Work", "sftp://nas/Documents/Work/2026"])
    #expect(RemoteURL.parent(of: url)?.absoluteString == "sftp://nas/Documents/Work")
    #expect(RemoteURL.parent(of: URL(string: "sftp://nas/")!) == nil)
    #expect(RemoteURL.name(of: url) == "2026" && RemoteURL.name(of: URL(string: "sftp://nas/")!) == "nas")
    #expect(Breadcrumbs.chain(for: url).count == 4 && Breadcrumbs.parent(of: url)?.absoluteString == "sftp://nas/Documents/Work")
}

@Test func aServerIsIdentifiedBySchemeHostAndPort() {
    #expect(RemoteURL.serverKey(URL(string: "SFTP://Nas/a/b")!) == "sftp://nas")
    #expect(RemoteURL.serverKey(URL(string: "ftp://nas:2121/a")!) == "ftp://nas:2121")
    #expect(RemoteURL.serverKey(URL(string: "sftp://nas/a")!) != RemoteURL.serverKey(URL(string: "ftp://nas/a")!))
}

@Test func aTypedRemoteAddressBecomesAURL() {
    #expect(RemoteURL.parse("sftp://nas/Documents")?.absoluteString == "sftp://nas/Documents")
    #expect(RemoteURL.parse("  ftp://nas  ")?.absoluteString == "ftp://nas/")
    #expect(RemoteURL.parse("sftp://nas/My Photos")?.absoluteString == "sftp://nas/My%20Photos")
    #expect(RemoteURL.parse("~/Documents") == nil)
    #expect(RemoteURL.parse("http://example.com") == nil)
    #expect(RemoteURL.parse("sftp://") == nil)
}

@Test func theRouterPicksThisMacOrTheOpenConnection() {
    let router = FileSystemRouter()
    let nas = InMemoryRemote(serverKey: "sftp://nas")
    #expect(router.filesystem(for: URL(fileURLWithPath: "/Users")) is LocalFileSystem)
    #expect(router.filesystem(for: URL(string: "sftp://nas/a")!) == nil)
    router.register(nas)
    #expect((router.filesystem(for: URL(string: "sftp://nas/a/b")!) as? InMemoryRemote) === nas)
    #expect(router.filesystem(for: URL(string: "sftp://other/a")!) == nil)
    #expect(router.serverKeys == ["sftp://nas"])
    router.remove(serverKey: "sftp://nas")
    #expect(router.serverKeys.isEmpty)
}

@Test func aServerListsFoldersFirstInNaturalOrderLikeALocalFolder() async throws {
    let nas = InMemoryRemote(serverKey: "sftp://nas")
    nas.add(folder: "/Docs"); nas.add(folder: "/archive")
    nas.add(file: "/file10.txt"); nas.add(file: "/file2.txt")
    let listed = try await nas.list(URL(string: "sftp://nas/")!)
    #expect(listed.map(\.name) == ["archive", "Docs", "file2.txt", "file10.txt"])
    #expect(listed.first?.url.absoluteString == "sftp://nas/archive")
    #expect(listed.first?.isFolder == true && listed.last?.isFolder == false)
}

@Test func aDroppedConnectionFailsListingsUntilItReconnects() async throws {
    let nas = InMemoryRemote(serverKey: "sftp://nas")
    nas.add(file: "/a.txt")
    nas.dropConnection()
    await #expect(throws: RemoteError.connectionLost) { try await nas.list(URL(string: "sftp://nas/")!) }
    try await nas.reconnect()
    #expect(try await nas.list(URL(string: "sftp://nas/")!).count == 1)
}

@Test func aFileOnAServerGetsItsKindFromItsName() {
    #expect(FolderItem.kind(forFileNamed: "Trip.pdf", isFolder: false) == "PDF document")
    #expect(FolderItem.kind(forFileNamed: "photo.JPG", isFolder: false) == "JPEG image")
    #expect(FolderItem.kind(forFileNamed: "Documents", isFolder: true) == "File folder")
    #expect(FolderItem.kind(forFileNamed: "README", isFolder: false) == "File")
    #expect(FolderItem.kind(forFileNamed: "data.zzqx", isFolder: false) == "ZZQX file")
}

private actor Counter {
    var value = 0
    func bump() { value += 1 }
}

// MARK: S3 (S-063)

private struct StubTransport: S3Transport {
    let answer: @Sendable (URLRequest) -> (Int, String)
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = answer(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Test func s3SignatureMatchesTheAWSDocsExample() {
    // "Example: GET Object" from the AWS Signature Version 4 docs.
    let date = ISO8601DateFormatter().date(from: "2013-05-24T00:00:00Z")!
    let headers = S3Signer.sign(
        method: "GET", url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!, headers: ["Range": "bytes=0-9"],
        credentials: .init(accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"),
        region: "us-east-1", date: date)
    #expect(headers["Authorization"] == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
}

@Test func s3ListingTurnsPrefixesIntoFoldersAndKeysIntoFiles() throws {
    let xml = """
    <?xml version="1.0"?><ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>b</Name><Prefix>docs/</Prefix>
    <IsTruncated>true</IsTruncated><NextContinuationToken>tok+1/=</NextContinuationToken>
    <Contents><Key>docs/a b.txt</Key><LastModified>2026-10-01T12:30:00.000Z</LastModified><Size>42</Size></Contents>
    <CommonPrefixes><Prefix>docs/sub/</Prefix></CommonPrefixes></ListBucketResult>
    """
    let page = try #require(S3Listing.parsePage(Data(xml.utf8)))
    #expect(page.folders == ["docs/sub/"])
    #expect(page.files.map(\.key) == ["docs/a b.txt"] && page.files.first?.size == 42 && page.files.first?.modified != nil)
    #expect(page.nextToken == "tok+1/=")
}

@Test func s3FollowsContinuationTokensAndOpensBucketsAsFolders() async throws {
    let calls = CallCounter()
    let transport = StubTransport { request in
        let query = request.url?.query ?? ""
        if request.url?.path == "/" {
            return (200, "<ListAllMyBucketsResult><Buckets><Bucket><Name>photos</Name><CreationDate>2026-01-01T00:00:00.000Z</CreationDate></Bucket></Buckets></ListAllMyBucketsResult>")
        }
        calls.add()
        if query.contains("continuation-token=next%2B1") {
            return (200, "<ListBucketResult><IsTruncated>false</IsTruncated><Contents><Key>docs/two.txt</Key><Size>2</Size></Contents></ListBucketResult>")
        }
        return (200, "<ListBucketResult><IsTruncated>true</IsTruncated><NextContinuationToken>next+1</NextContinuationToken><Contents><Key>docs/</Key><Size>0</Size></Contents><Contents><Key>docs/one.txt</Key><Size>1</Size></Contents><CommonPrefixes><Prefix>docs/sub/</Prefix></CommonPrefixes></ListBucketResult>")
    }
    let s3 = S3FileSystem(endpoint: "s3.example.com:9000", region: "us-east-1", credentials: .init(accessKey: "k", secretKey: "s"), transport: transport)
    #expect(s3.serverKey == "s3://s3.example.com:9000")
    let top = try await s3.list(RemoteURL.make(scheme: "s3", host: "s3.example.com", port: 9000))
    #expect(top.map(\.name) == ["photos"] && top[0].isFolder)
    let docs = try await s3.list(RemoteURL.make(scheme: "s3", host: "s3.example.com", port: 9000, path: "/photos/docs"))
    #expect(Set(docs.map(\.name)) == ["sub", "one.txt", "two.txt"])
    #expect(calls.value == 2)
    #expect(docs.first { $0.name == "sub" }?.url.path == "/photos/docs/sub")
}

@Test func s3WrongKeyIsAccessDenied() async {
    let transport = StubTransport { _ in (403, "<Error><Code>InvalidAccessKeyId</Code><Message>The AWS Access Key Id you provided does not exist.</Message></Error>") }
    let s3 = S3FileSystem(endpoint: "s3.amazonaws.com", region: "us-east-1", credentials: .init(accessKey: "bad", secretKey: "bad"), transport: transport)
    await #expect(throws: RemoteError.denied("Access denied.")) { try await s3.list(URL(string: "s3://s3.amazonaws.com/")!) }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

// MARK: SFTP (S-062)

private final class ScriptedRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [(exe: String, args: [String], input: String, env: [String: String])] = []
    let answer: @Sendable (String, [String], String) -> ProcessResult
    init(_ answer: @escaping @Sendable (String, [String], String) -> ProcessResult) { self.answer = answer }
    func run(_ executable: String, _ arguments: [String], input: String, environment: [String: String]) async throws -> ProcessResult {
        lock.withLock { calls.append((executable, arguments, input, environment)) }
        return answer(executable, arguments, input)
    }
}

private func sftpSystem(_ runner: ProcessRunner, login: SFTPFileSystem.Login = .password("pw"), known: URL? = nil) -> SFTPFileSystem {
    SFTPFileSystem(host: "NAS.local", user: "me", login: login,
                   knownHosts: known ?? FileManager.default.temporaryDirectory.appending(path: "pane-kh-\(UUID().uuidString)"),
                   workFolder: URL(fileURLWithPath: "/tmp/pane-ssh-test"), runner: runner,
                   now: { ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")! })
}

@Test func sftpListingReadsSpacesNonASCIIAndLinks() {
    let output = """
    sftp> ls -ln "/srv/My Docs"
    drwxr-xr-x    2 1000     1000         4096 Oct 30 09:15 Año nuevo
    -rw-r--r--    1 1000     1000       118000 Mar  3  2024 Budget 2026.xlsx
    -rw-r--r--    1 1000     1000          204 Dec 25 08:00 notes.txt
    lrwxrwxrwx    1 0        0              11 Jan  1 10:00 www -> /var/www
    drwxr-xr-x    5 1000     1000         4096 Oct 30 09:15 .
    """
    let items = SFTPText.parseListing(output, folder: URL(string: "sftp://nas/srv/My%20Docs")!,
                                      now: ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")!)
    #expect(items.map(\.name) == ["Año nuevo", "Budget 2026.xlsx", "notes.txt", "www"])
    #expect(items[0].isFolder && items[0].size == nil)
    #expect(items[1].size == 118000 && !items[1].isFolder)
    #expect(items[0].url.path == "/srv/My Docs/Año nuevo" && RemoteURL.name(of: items[0].url) == "Año nuevo")
    let year = { (item: FolderItem) in Calendar(identifier: .gregorian).component(.year, from: item.modified!) }
    #expect(year(items[1]) == 2024 && year(items[2]) == 2025)   // Dec 25 is in the future this year, so last year
}

@Test func sftpQuotingKeepsOddPathsInOnePiece() {
    #expect(SFTPText.quote("/a b/é") == "\"/a b/é\"")
    #expect(SFTPText.quote("/say \"hi\"\\") == "\"/say \\\"hi\\\"\\\\\"")
}

@Test func sshFailuresBecomeWordsAPersonCanUse() {
    #expect(SFTPText.classify(stderr: "me@nas: Permission denied (publickey,password).") == .denied("Access denied."))
    #expect(SFTPText.classify(stderr: "@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@\nHost key verification failed.") == .hostKeyChanged)
    #expect(SFTPText.classify(stderr: "ssh: connect to host nas port 22: Connection refused") == .connectionLost)
    #expect(SFTPText.fingerprint(fromKeygen: "256 SHA256:abcDEF nas (ED25519)") == "SHA256:abcDEF")
}

@Test func sftpListsThroughOneBatchAndKeepsTheSecretOutOfArguments() async throws {
    let runner = ScriptedRunner { _, _, _ in
        ProcessResult(stdout: "drwxr-xr-x 2 1 1 4096 Oct 30 09:15 Photos\n-rw-r--r-- 1 1 1 5 Oct 30 09:15 a.txt\n", stderr: "", status: 0)
    }
    let system = sftpSystem(runner)
    #expect(system.serverKey == "sftp://nas.local")
    let items = try await system.list(URL(string: "sftp://nas.local/srv/My%20Docs")!)
    #expect(items.map(\.name) == ["Photos", "a.txt"])
    let call = try #require(runner.calls.first)
    #expect(call.exe == "/usr/bin/sftp" && call.input == "ls -ln \"/srv/My Docs\"\n")
    #expect(call.env["PANE_SFTP_SECRET"] == "pw" && !call.args.joined().contains("pw"))
    #expect(call.args.contains("StrictHostKeyChecking=yes") && call.args.contains("me@nas.local") && !call.args.contains("BatchMode=yes"))
}

@Test func sftpKeyLoginNamesTheKeyAndNeverPromptsWithoutAPassphrase() async throws {
    let runner = ScriptedRunner { _, _, _ in ProcessResult(stdout: "Remote working directory: /home/me\n", stderr: "", status: 0) }
    let home = try await sftpSystem(runner, login: .key(path: "/Users/me/.ssh/id_ed25519", passphrase: "")).start()
    #expect(home == "/home/me")
    let args = try #require(runner.calls.first).args
    #expect(args.contains("/Users/me/.ssh/id_ed25519") && args.contains("BatchMode=yes") && args.contains("IdentitiesOnly=yes"))
}

@Test func sftpAsksBeforeTrustingANewServerThenRemembersIt() async throws {
    let known = FileManager.default.temporaryDirectory.appending(path: "pane-kh-\(UUID().uuidString)")
    let trusted = Box()
    let runner = ScriptedRunner { exe, _, _ in
        switch exe {
        case "/usr/bin/ssh-keyscan": return ProcessResult(stdout: "# nas.local\nnas.local ssh-rsa AAAArsa\nnas.local ssh-ed25519 AAAAed\n", stderr: "", status: 0)
        case "/usr/bin/ssh-keygen": return ProcessResult(stdout: "256 SHA256:fp123 nas.local (ED25519)\n", stderr: "", status: 0)
        default:
            return trusted.value
                ? ProcessResult(stdout: "Remote working directory: /\n", stderr: "", status: 0)
                : ProcessResult(stdout: "", stderr: "No ED25519 host key is known for nas.local and you have requested strict checking.\nHost key verification failed.\n", status: 255)
        }
    }
    let system = sftpSystem(runner, known: known)
    await #expect(throws: RemoteError.unknownHostKey(fingerprint: "SHA256:fp123", keyLine: "nas.local ssh-ed25519 AAAAed")) { try await system.start() }
    try system.trust(keyLine: "nas.local ssh-ed25519 AAAAed")
    trusted.value = true
    #expect(try await system.start() == "/")
    #expect(try String(contentsOf: known, encoding: .utf8) == "nas.local ssh-ed25519 AAAAed\n")
}

@Test func sftpStopsWhenAKnownServersKeyChanges() async {
    let runner = ScriptedRunner { _, _, _ in ProcessResult(stdout: "", stderr: "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!\nHost key verification failed.\n", status: 255) }
    await #expect(throws: RemoteError.hostKeyChanged) { try await sftpSystem(runner).start() }
    #expect(runner.calls.allSatisfy { $0.exe == "/usr/bin/sftp" })   // it never looks for a key to trust
}

private final class Box: @unchecked Sendable { var value = false }

// MARK: FTP (S-061)

@Test func ftpListingReadsUnixAndWindowsFormats() {
    let unix = """
    total 12
    drwxr-xr-x   2 ftp      ftp          4096 Oct 30 09:15 Año nuevo
    -rw-r--r--   1 ftp      ftp        118000 Mar  3  2024 Budget 2026.xlsx
    """
    let iis = """
    10-30-26  09:15AM       <DIR>          Public Files
    03-03-2024  12:05PM              118000 Budget 2026.xlsx
    11-01-26  12:00AM                 204 notes.txt
    """
    let now = ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")!
    let a = FTPText.parseListing(unix, folder: URL(string: "ftp://h/")!, now: now)
    #expect(a.map(\.name) == ["Año nuevo", "Budget 2026.xlsx"] && a[0].isFolder && a[1].size == 118000)
    let b = FTPText.parseListing(iis, folder: URL(string: "ftp://h/")!, now: now)
    #expect(b.map(\.name) == ["Public Files", "Budget 2026.xlsx", "notes.txt"])
    #expect(b[0].isFolder && b[1].size == 118000 && b[2].size == 204)
    let calendar = Calendar(identifier: .gregorian)
    #expect(calendar.component(.hour, from: b[1].modified!) == 12 && calendar.component(.hour, from: b[2].modified!) == 0)
    #expect(calendar.component(.year, from: b[1].modified!) == 2024)
}

@Test func ftpFailuresBecomeWordsAPersonCanUse() {
    #expect(FTPText.classify(status: 67, stderr: "curl: (67) Access denied: 530") == .denied("Access denied."))
    #expect(FTPText.classify(status: 7, stderr: "Failed to connect") == .connectionLost)
    #expect(FTPText.classify(status: 60, stderr: "") == .other("Unable to verify this server's certificate."))
    #expect(FTPText.classify(status: 64, stderr: "").message.contains("does not support TLS"))
}

@Test func ftpSendsTheLoginOnStdinAndAsksForTLSWhenToldTo() async throws {
    let runner = ScriptedRunner { _, _, _ in ProcessResult(stdout: "drwxr-xr-x 2 a b 4096 Oct 30 09:15 Docs\n", stderr: "", status: 0) }
    let tls = FTPFileSystem(host: "FTP.Example.com", port: 2121, user: "me", password: "p\"w\\x", secure: true, runner: runner)
    #expect(tls.serverKey == "ftps://ftp.example.com:2121")
    let items = try await tls.list(URL(string: "ftps://ftp.example.com:2121/My%20Files")!)
    #expect(items.map(\.name) == ["Docs"])
    let call = try #require(runner.calls.first)
    #expect(call.exe == "/usr/bin/curl" && call.args.contains("--ssl-reqd") && !call.args.joined().contains("p\"w"))
    #expect(call.input.contains("url = \"ftps://ftp.example.com:2121/My%20Files/\""))
    #expect(call.input.contains("user = \"me:p\\\"w\\\\x\""))
    let plain = FTPFileSystem(host: "h", user: "me", password: "pw", secure: false, runner: runner)
    _ = try await plain.list(URL(string: "ftp://h/")!)
    #expect(!(runner.calls.last?.args.contains("--ssl-reqd") ?? true))
}

@Test func ftpWrongPasswordIsAccessDenied() async {
    let runner = ScriptedRunner { _, _, _ in ProcessResult(stdout: "", stderr: "curl: (67) Access denied: 530", status: 67) }
    await #expect(throws: RemoteError.denied("Access denied.")) {
        try await FTPFileSystem(host: "h", user: "me", password: "bad", secure: false, runner: runner).start()
    }
}

// MARK: Copy between this Mac and a server (S-064)

private func scratchFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "pane-xfer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func serverURL(_ path: String) -> URL { RemoteURL.make(scheme: "sftp", host: "nas", path: path) }

private func transferSetup() -> (TransferOperations, InMemoryRemote, URL) {
    let router = FileSystemRouter()
    let nas = InMemoryRemote(serverKey: "sftp://nas")
    router.register(nas)
    return (TransferOperations(router: router), nas, scratchFolder())
}

private let skipAll: FileOperations.Resolver = { _ in ConflictDecision(choice: .skip) }

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

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [OperationProgress] = []
    func add(_ value: OperationProgress) { lock.withLock { items.append(value) } }
    var values: [OperationProgress] { lock.withLock { items } }
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

private struct FileStubTransport: S3Transport {
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

private final class Collected2: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ value: String) { lock.withLock { items.append(value) } }
    var values: [String] { lock.withLock { items } }
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

private struct ListingStub: S3Transport {
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

private func editSetup() -> (RemoteEdits, InMemoryRemote, URL) {
    let router = FileSystemRouter()
    let nas = InMemoryRemote(serverKey: "sftp://nas")
    router.register(nas)
    nas.add(folder: "/Docs"); nas.add(file: "/Docs/Notes.txt", contents: Data("first".utf8))
    let root = scratchFolder().appending(path: "edits")
    return (RemoteEdits(router: router, root: root), nas, root)
}

private func save(_ text: String, to file: URL) throws {
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

// MARK: Saved connections (S-067)

@Test func savedConnectionsKeepSettingsOnlyAndNoSecret() throws {
    var list = SavedConnections()
    list.save(SavedConnection(kind: .sftp, host: "NAS.local", port: 2222, user: "me", useKey: true, keyPath: "/Users/me/.ssh/id_ed25519"))
    list.save(SavedConnection(kind: .s3, host: "minio.local", port: 9000, user: "AKIAEXAMPLE", region: "eu-west-1"))
    list.save(SavedConnection(kind: .ftps, host: "ftp.example.com", user: "web"))
    let text = String(decoding: list.data, as: UTF8.self)
    #expect(text.contains("nas.local") && text.contains("AKIAEXAMPLE") && text.contains("eu-west-1"))
    #expect(!text.lowercased().contains("password") && !text.lowercased().contains("secret"), "the saved list has no field for a secret")
    #expect(SavedConnections(data: list.data) == list)
    #expect(SavedConnections(data: Data("not json".utf8)).items.isEmpty && SavedConnections(data: nil).items.isEmpty)
}

@Test func savedConnectionsNameTheirServerAndUpdateInsteadOfDuplicating() {
    var list = SavedConnections()
    let sftp = SavedConnection(kind: .sftp, host: "nas.local", user: "me")
    list.save(sftp)
    #expect(sftp.serverKey == "sftp://nas.local" && sftp.displayName == "nas.local (SFTP)" && sftp.detail == "me@nas.local")
    #expect(SavedConnection(kind: .s3, host: "minio.local", port: 9000, user: "k").serverKey == "s3://minio.local:9000")
    #expect(SavedConnection(kind: .ftps, host: "h", user: "u").serverKey == "ftps://h" && SavedConnection(kind: .ftps, host: "h", user: "u").address.absoluteString == "ftps://h/")
    list.save(SavedConnection(kind: .sftp, host: "nas.local", user: "me", useKey: true, keyPath: "/k"))
    #expect(list.items.count == 1 && list.items[0].id == sftp.id && list.items[0].useKey, "the same server and user updates the entry")
    list.save(SavedConnection(kind: .sftp, host: "other.local", user: "me"), replacing: sftp.id)
    #expect(list.items.map(\.host) == ["other.local"] && list.items[0].id == sftp.id, "editing replaces the entry being edited, and keeps its id")
    let removed = list.remove(list.items[0].id)
    #expect(removed?.host == "other.local" && list.items.isEmpty)
    #expect(list.connection(forServerKey: "sftp://other.local") == nil)
}
