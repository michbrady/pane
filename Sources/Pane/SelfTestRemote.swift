import AppKit
import PaneKit

/// Self-test: servers (S-060 to S-067). Today: browsing a server like a folder. A server in memory
/// stands in for a real one, so nothing touches a network.
extension SelfTest {
    static func remote(_ c: Context) async {
        let model = c.model
        @MainActor func settle() async { await Wait.settle(c.model) }

        // S-060 Browse a remote place like a folder
        let nas = InMemoryRemote(serverKey: "sftp://nas")
        nas.add(folder: "/Docs"); nas.add(folder: "/archive")
        nas.add(file: "/file10.txt", size: 2048); nas.add(file: "/file2.txt"); nas.add(file: "/Docs/plan.txt")
        model.connected(nas)
        check("a connected server shows under Connections", model.places.connectionRoots.map(\.name) == ["nas (SFTP)"], "\(model.places.connectionRoots.map(\.name))")
        let top = URL(string: "sftp://nas/")!
        check("a server's row has no folders under it, and never lists this Mac's", model.places.connectionRoots.first?.children == nil)
        model.tab.go(to: top)
        await settle()
        check("a server's folder lists folders first, in natural order, like a local one",
              model.tab.items.map(\.name) == ["archive", "Docs", "file2.txt", "file10.txt"], "\(model.tab.items.map(\.name))")
        check("items carry their server address", model.tab.items.first?.url.absoluteString == "sftp://nas/archive")
        check("a server's top is named for the server", model.tab.currentName == "nas")
        check("the tree selects the server's row", model.places.navSelection == "conn:sftp://nas/", model.places.navSelection ?? "nil")
        check("a server tab does not watch or poll", model.tab.isRemote && model.tab.pollInterval == nil)
        let docs = model.tab.items.first { $0.name == "Docs" }!.url
        model.tab.open([docs])
        await settle()
        check("opening a server folder shows it", model.tab.currentFolder.absoluteString == "sftp://nas/Docs" && model.tab.items.map(\.name) == ["plan.txt"])
        check("the breadcrumbs run from the server down", Breadcrumbs.chain(for: model.tab.currentFolder).map { Locations.displayName(for: $0) } == ["nas", "Docs"])
        check("Go up works on a server", model.tab.canGoUp)
        model.tab.goUp()
        await settle()
        check("and returns to the server's top", model.tab.currentFolder.absoluteString == "sftp://nas/")

        model.beginEditingAddress()
        check("the Address bar shows a server address", model.addressText == "sftp://nas/", model.addressText)
        model.addressText = "sftp://other/x"
        model.commitAddress()
        check("a server that is not connected is refused with a way forward",
              model.addressError == "Not connected to that server. Use Go > Connect to Server.", model.addressError ?? "nil")
        model.addressText = "sftp://nas/archive"
        model.commitAddress()
        await settle()
        check("a typed server address goes there", model.tab.currentFolder.absoluteString == "sftp://nas/archive")
        model.cancelEditingAddress()

        model.tab.go(to: URL(string: "sftp://ghost/")!)
        await settle()
        check("a server with no open connection says so", model.tab.loadProblem == .notConnected && model.tab.loadError == "Not connected to this server.")

        nas.slowDown(by: .seconds(3))
        model.tab.go(to: docs)
        await Wait.until(2) { model.tab.isSlow }
        check("going into a server's folder is not undone by the tree's selection", model.tab.currentFolder == docs, model.tab.currentFolder.absoluteString)
        check("a slow folder shows Loading… after half a second", model.tab.isSlow)
                model.tab.cancelLoad()
        nas.slowDown(by: .zero)
        await settle()
        check("Cancel stops waiting and goes back, and the slow answer is ignored",
              !model.tab.isLoading && model.tab.currentFolder != docs && !model.tab.items.contains { $0.name == "plan.txt" },
              "\(model.tab.currentFolder.absoluteString) \(model.tab.items.map(\.name))")

        model.tab.go(to: top)
        await settle()
        nas.dropConnection()
        model.tab.reload()
        await settle()
        check("a dropped connection says so and keeps the last list, dimmed",
              model.tab.loadProblem == .connectionLost && model.tab.loadError == "Connection lost." && model.tab.isStale && !model.tab.items.isEmpty)
        model.tab.reconnect()
        await Wait.until { !model.tab.isStale }
        await settle()
        check("Reconnect brings the list back", !model.tab.isStale && model.tab.loadProblem == nil && model.tab.items.count == 4)

        model.tab.selection = Set(model.tab.items.prefix(1).map(\.url))
        model.actions.trashSelection()
        check("changing files on a server is blocked, with a message", model.actions.alertMessage?.contains("later step") == true)
        model.actions.alertMessage = nil
        model.actions.newFolder()
        check("so is New Folder", model.actions.alertMessage?.contains("later step") == true)
        model.actions.alertMessage = nil
        model.actions.drop([c.docs.appending(path: "Notes.txt")], into: top, option: false, command: false)
        check("so is dropping a local file onto a server", model.actions.alertMessage?.contains("later step") == true)
        model.actions.alertMessage = nil
        check("no local file was touched by any of that", FileManager.default.fileExists(atPath: c.docs.appending(path: "Notes.txt").path))

        model.disconnect(serverKey: "sftp://nas")
        await settle()
        check("Eject on a server closes it and removes its row", model.router.serverKeys.isEmpty && model.places.connectionRoots.isEmpty)
        check("a tab that was on it goes home", !model.tab.isRemote)
        model.tab.go(to: c.docs)
        await settle()
    }
}
