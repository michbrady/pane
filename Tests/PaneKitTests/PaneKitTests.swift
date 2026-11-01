import Foundation
import Testing
@testable import PaneKit

private func makeTree() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-test-\(UUID().uuidString)")
    let fm = FileManager.default
    for dir in ["Beta", "alpha", "My Folder"] {
        try fm.createDirectory(at: root.appending(path: dir), withIntermediateDirectories: true)
    }
    for file in ["file10.txt", "file2.txt", ".hidden"] {
        try Data("x".utf8).write(to: root.appending(path: file))
    }
    return root
}

@Test func foldersComeFirstThenNaturalOrder() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let names = try FolderLister.list(root).map(\.name)
    #expect(names == ["alpha", "Beta", "My Folder", "file2.txt", "file10.txt"])
}

@Test func hiddenFilesShowOnRequest() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try FolderLister.list(root, showHidden: true).map(\.name).contains(".hidden"))
}

@Test func foldersHaveNoSize() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let items = try FolderLister.list(root)
    #expect(items.first { $0.name == "alpha" }?.size == nil)
    #expect(items.first { $0.name == "file2.txt" }?.size == 1)
}

@Test func largeFolderListsQuickly() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "pane-big-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for i in 0..<1000 { try Data().write(to: root.appending(path: "f\(i).txt")) }
    let start = Date()
    #expect(try FolderLister.list(root).count == 1000)
    #expect(Date().timeIntervalSince(start) < 1)
}

@Test func historyKeepsOrderAndClearsForward() {
    var h = NavigationHistory(start: URL(filePath: "/a"))
    h.visit(URL(filePath: "/b"))
    h.visit(URL(filePath: "/c"))
    #expect(h.goBack() == URL(filePath: "/b"))
    #expect(h.canGoForward)
    h.visit(URL(filePath: "/d"))
    #expect(!h.canGoForward)
    #expect(h.goBack() == URL(filePath: "/b"))
    #expect(h.goBack() == URL(filePath: "/a"))
    #expect(h.goBack() == nil)
}

@Test func resolverHandlesTildeAndSpaces() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let home = root
    #expect(PathResolver.resolve("~", home: home, base: root) == .success(home.standardizedFileURL))
    #expect(PathResolver.resolve("~/My Folder", home: home, base: root) == .success(root.appending(path: "My Folder").standardizedFileURL))
    #expect(PathResolver.resolve("\"~/My Folder\"", home: home, base: root) == .success(root.appending(path: "My Folder").standardizedFileURL))
    #expect(PathResolver.resolve("My\\ Folder", home: home, base: root) == .success(root.appending(path: "My Folder").standardizedFileURL))
    #expect(PathResolver.resolve("  ", home: home, base: root) == .failure(.empty))
    #expect(PathResolver.resolve("~/Nope", home: home, base: root) == .failure(.notFound))
    #expect(PathResolver.resolve("~/file2.txt", home: home, base: root) == .failure(.notAFolder))
}

@Test func breadcrumbsRunFromRootAndParentStopsAtRoot() {
    let chain = Breadcrumbs.chain(for: URL(filePath: "/Users/me/Documents"))
    #expect(chain.map(\.path) == ["/", "/Users", "/Users/me", "/Users/me/Documents"])
    #expect(Breadcrumbs.parent(of: URL(filePath: "/Users")) == URL(filePath: "/"))
    #expect(Breadcrumbs.parent(of: URL(filePath: "/")) == nil)
}

@Test func f6CyclesListNavigationAddressAndShiftF6GoesBack() {
    #expect(FocusCycle.next(after: .list) == .navigation)
    #expect(FocusCycle.next(after: .navigation) == .address)
    #expect(FocusCycle.next(after: .address) == .list)
    #expect(FocusCycle.next(after: .list, reverse: true) == .address)
    #expect(FocusCycle.next(after: .address, reverse: true) == .navigation)
    #expect(FocusCycle.next(after: .list, navigationShown: false) == .address)
    #expect(FocusCycle.next(after: .address, reverse: true, navigationShown: false) == .list)
}

@Test func voiceOverReadsNameKindAndSize() {
    let file = FolderItem(url: URL(fileURLWithPath: "/a/Budget.xlsx"), name: "Budget.xlsx", isFolder: false, size: 118_000, modified: nil, kind: "Excel Workbook")
    #expect(ItemSpeech.label(for: file) == "Budget.xlsx, Excel Workbook, 118 KB")
    #expect(ItemSpeech.label(for: file, showExtensions: false) == "Budget, Excel Workbook, 118 KB")
    let folder = FolderItem(url: URL(fileURLWithPath: "/a/Work"), name: "Work", isFolder: true, size: nil, modified: nil, kind: "")
    #expect(ItemSpeech.label(for: folder) == "Work, Folder")
    let cloud = FolderItem(url: URL(fileURLWithPath: "/a/n.txt"), name: "n.txt", isFolder: false, size: 5, modified: nil, kind: "Text", isOnlineOnly: true)
    #expect(ItemSpeech.label(for: cloud).hasSuffix("Online only"))
}

@Test func theContextMenuHasAnIconRowThenTheList() {
    let file = ContextMenuPlan(selectionCount: 1, hasFolder: false, isOnlyFolder: false, onServer: false, isPinned: false)
    #expect(file.iconRow == [.cut, .copy, .rename, .delete])
    #expect(file.items == [.open, .openWith, .properties, .tags])
    let folder = ContextMenuPlan(selectionCount: 1, hasFolder: true, isOnlyFolder: true, onServer: false, isPinned: false)
    #expect(folder.items == [.open, .properties, .tags, .openInNewTab, .openInTerminal, .pin])
    #expect(ContextMenuPlan(selectionCount: 1, hasFolder: true, isOnlyFolder: true, onServer: false, isPinned: true).items.last == .unpin)
    let many = ContextMenuPlan(selectionCount: 3, hasFolder: false, isOnlyFolder: false, onServer: false, isPinned: false)
    #expect(many.iconRow == [.cut, .copy, .delete], "Rename is for one item")
    let remote = ContextMenuPlan(selectionCount: 1, hasFolder: true, isOnlyFolder: true, onServer: true, isPinned: false)
    #expect(remote.items == [.open, .openInNewTab], "a server offers no Terminal, pins, Open With, Properties, or Tags")
}
