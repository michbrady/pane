import AppKit
import PaneKit

/// Self-test: browsing (S-001 to S-008).
extension SelfTest {
    static func browse(_ c: Context) async {
        let model = c.model, docs = c.docs, work = c.work
        @MainActor func settle() async { await Wait.settle(c.model) }

        model.tab.go(to: docs)
        await settle()
        check("a folder lists its items", model.tab.items.count >= 4, "\(model.tab.items.count) items")
        check("folders come first", model.tab.items.first?.isFolder == true)
        let names = model.tab.items.map(\.name)
        check("names sort naturally", (names.firstIndex(of: "file2.txt") ?? 0) < (names.firstIndex(of: "file10.txt") ?? 0))

        model.tab.open([work])
        await settle()
        check("open on a folder shows its contents", model.tab.currentFolder.path == work.standardizedFileURL.path)
        check("Back is available", model.tab.canGoBack)
        model.tab.goUp()
        check("Go up shows the parent", model.tab.currentFolder.path == docs.standardizedFileURL.path)
        model.tab.goBack()
        check("Go back returns to the last folder", model.tab.currentFolder.path == work.standardizedFileURL.path)
        model.tab.goForward()
        check("Go forward returns", model.tab.currentFolder.path == docs.standardizedFileURL.path)

        model.beginEditingAddress()
        check("the address field shows ~ paths", model.addressText == "~/Documents", model.addressText)
        model.addressText = "~/Documents/Work"
        model.commitAddress()
        await settle()
        check("a typed path goes there", model.tab.currentFolder.path == work.standardizedFileURL.path)
        model.beginEditingAddress()
        model.addressText = "~/Nope"
        model.commitAddress()
        check("a bad path shows an error and stays", model.addressError != nil && model.isEditingAddress)
        model.cancelEditingAddress()
        check("Escape restores the breadcrumbs", !model.isEditingAddress)

        check("the tree follows the current folder", model.navSelection == "home:" + work.standardizedFileURL.path, model.navSelection ?? "nil")
        check("the tree opens the folders above", model.expanded.contains("home:" + docs.standardizedFileURL.path))

        try? Data("new".utf8).write(to: work.appending(path: "Added.txt"))
        await Wait.until { model.tab.items.contains { $0.name == "Added.txt" } }
        check("a file added from outside appears", model.tab.items.contains { $0.name == "Added.txt" })
    }
}
