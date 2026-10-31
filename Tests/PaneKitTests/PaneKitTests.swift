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
