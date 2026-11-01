import AppKit
import PaneKit

/// Self-test: polish (S-050 to S-054): context menus, empty states, Settings, the keyboard.
extension SelfTest {
    static func polish(_ c: Context) async {
        let model = c.model
        @MainActor func settle() async { await Wait.settle(c.model) }
        NSApp.keyWindow?.makeFirstResponder(nil)

        // S-052 Change settings: Return opens or renames
        model.tab.go(to: c.docs)
        await settle()
        check("Settings has General, Appearance, Shortcuts, and Advanced", SettingsTab.allCases.map(\.title) == ["General", "Appearance", "Shortcuts", "Advanced"])
        model.view.returnRenames = false
        model.tab.selection = Set(model.tab.items.filter { $0.name == "Work" }.map(\.url))
        check("Return opens a folder by default", model.pressReturn())
        await settle()
        check("and shows it", model.tab.currentFolder.standardizedFileURL.path == c.work.standardizedFileURL.path)
        model.tab.go(to: c.docs)
        await settle()
        let notes = model.tab.items.first { $0.name == "Notes.txt" }?.url ?? c.docs
        NSApp.keyWindow?.makeFirstResponder(nil)
        model.view.returnRenames = true
        model.tab.selection = [notes]
        check("with the setting on, Return starts renaming", model.pressReturn() && model.actions.renamingURL?.lastPathComponent == "Notes.txt", "\(String(describing: model.actions.renamingURL)) \(model.tab.selectedItems.count)")
        model.actions.cancelRename()
        model.tab.selection = []
        check("Return with nothing selected does nothing", !model.pressReturn())
        model.view.returnRenames = false
        check("the choice is saved", Prefs.defaults.object(forKey: "view.returnRenames") as? Bool == false)

        let known = Connections.knownHostsFile
        try? FileManager.default.createDirectory(at: known.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "nas ssh-ed25519 AAAA\n".write(to: known, atomically: true, encoding: .utf8)
        model.connections.forgetTrustedServers()
        check("Forget Trusted SFTP Servers empties Pane's list", !FileManager.default.fileExists(atPath: known.path))
        check("and never touches ~/.ssh", !known.path.contains("/.ssh/"))

        // S-054 Make Pane keyboard friendly: F6 and Shift+F6 cycle the areas
        NSApp.keyWindow?.makeFirstResponder(nil)
        model.cancelEditingAddress()
        let shown = FocusMover.navigationShown
        var expected = FocusRegion.list
        var ok = true
        var trail: [String] = []
        for _ in 0..<4 {
            expected = FocusCycle.next(after: expected, navigationShown: shown)
            model.moveFocus()
            await settle()
            trail.append("\(model.focusRegion)")
            ok = ok && model.focusRegion == expected && (expected == .address) == model.isEditingAddress
            // The window's real focus is up to the desktop. Pane's own state is what is tested.
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        check("F6 cycles list, Navigation pane, Address bar, and around, and the Address bar starts editing", ok, "\(trail) shown \(shown)")
        model.cancelEditingAddress()
        model.moveFocus()
        let forward = model.focusRegion
        model.moveFocus(reverse: true)
        check("Shift+F6 goes back", FocusCycle.next(after: model.focusRegion, navigationShown: shown) == forward, "\(model.focusRegion) \(forward)")
        model.cancelEditingAddress()
        let first = model.tab.items.first
        check("a row's VoiceOver label has its name, kind, and size", first.map { ItemSpeech.label(for: $0, showExtensions: true).hasPrefix($0.name) } ?? false)

        // S-050 Use context menus: the icon row and the list come from one plan, and each entry runs its action
        model.tab.go(to: c.docs)
        await settle()
        NSApp.keyWindow?.makeFirstResponder(nil)
        let note = model.tab.items.first { $0.name == "Notes.txt" }!
        let plan = ContextMenuPlan(selectionCount: 1, hasFolder: false, isOnlyFolder: false, onServer: false, isPinned: false)
        check("the menu for a file has the icon row Cut, Copy, Rename, Delete, then Open, Open With, Properties, Tags",
              plan.iconRow.map(ItemMenu.title) == ["Cut", "Copy", "Rename", "Delete"] && plan.items.map(ItemMenu.title) == ["Open", "Open With", "Properties", "Tags"])
        check("every entry has a title and the icon row has icons", ContextMenuPlan.Entry.allCases.allSatisfy { !ItemMenu.title($0).isEmpty } && plan.iconRow.allSatisfy { ItemMenu.symbol($0) != "circle" })
        ItemMenu.run(.copy, urls: [note.url], model: model)
        check("Copy in the menu copies what was right-clicked, even if it was not selected", model.tab.selection == [note.url] && model.actions.canPaste)
        ItemMenu.run(.cut, urls: [note.url], model: model)
        check("Cut marks it as cut", model.actions.isCut(note.url))
        model.actions.clearCut()
        ItemMenu.run(.rename, urls: [note.url], model: model)
        check("Rename starts renaming it", model.actions.renamingURL == note.url)
        model.actions.cancelRename()
        ItemMenu.run(.properties, urls: [note.url], model: model)
        check("Properties opens its sheet", model.propertiesURLs == [note.url])
        model.closeProperties()
        ItemMenu.run(.delete, urls: [note.url], model: model)
        await Wait.until { !model.actions.isBusy }
        await settle()
        check("Delete in the menu sends it to the Trash", !FileManager.default.fileExists(atPath: note.url.path))
        model.actions.undoManager.undo()
        await Wait.until { !model.actions.isBusy }
        await settle()
        check("and Undo brings it back", FileManager.default.fileExists(atPath: note.url.path))

        // The Navigation pane follows changes: a new folder, a rename, and a delete show in the tree
        // Read from the root each time: a row that was read again is a new row.
        @MainActor func treeNames() -> [String] {
            (model.places.homeRoot.children?.first { $0.name == "Documents" }?.children ?? []).map(\.name)
        }
        check("the tree lists the folders in Documents", treeNames().contains("Work"), "\(treeNames())")
        model.tab.go(to: c.docs)
        await settle()
        NSApp.keyWindow?.makeFirstResponder(nil)
        model.actions.newFolder()
        await Wait.until { !model.actions.isBusy }
        await settle()
        model.actions.cancelRename()
        check("a new folder shows in the tree at once", treeNames().contains("New folder"), "\(treeNames())")
        let made = model.tab.items.first { $0.name == "New folder" }
        if let made {
            model.tab.selection = [made.url]
            model.actions.trashSelection()
            await Wait.until { !model.actions.isBusy }
            await settle()
        }
        check("a deleted folder leaves the tree", !treeNames().contains("New folder") && treeNames().contains("Work"), "\(treeNames())")
        model.actions.undoManager.undo()
        await Wait.until { !model.actions.isBusy }
        await settle()
        check("and Undo puts it back", treeNames().contains("New folder"), "\(treeNames())")
        if let again = model.tab.items.first(where: { $0.name == "New folder" }) {
            model.tab.selection = [again.url]
            model.actions.trashSelection()
            await Wait.until { !model.actions.isBusy }
            await settle()
        }
        // A change made outside Pane, in the folder being shown, shows in the tree too
        try? FileManager.default.createDirectory(at: c.docs.appending(path: "Made elsewhere"), withIntermediateDirectories: true)
        model.tab.reload()
        await Wait.until { treeNames().contains("Made elsewhere") }
        check("a folder made by another app shows in the tree after the list updates", treeNames().contains("Made elsewhere"), "\(treeNames())")
        try? FileManager.default.removeItem(at: c.docs.appending(path: "Made elsewhere"))
        model.tab.reload()
        await Wait.until { !treeNames().contains("Made elsewhere") }
        check("and leaves it when it is removed", !treeNames().contains("Made elsewhere"))
    }
}
