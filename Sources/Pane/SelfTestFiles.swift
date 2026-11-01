import AppKit
import PaneKit

/// Self-test: file operations (S-010 to S-017): copy, cut, conflicts, Trash, Undo, rename, drag.
extension SelfTest {
    static func files(_ c: Context) async {
        let model = c.model, home = c.home, docs = c.docs, work = c.work, drop = c.drop
        let fm = FileManager.default
        @MainActor func settle() async { await Wait.settle(c.model) }
        // S-010 Copy and paste
        model.tab.go(to: docs)
        await settle()
        let notes = docs.appending(path: "Notes.txt")
        model.tab.selection = [notes]
        model.actions.copySelection()
        model.tab.go(to: work)
        model.actions.paste()
        await settle()
        check("Paste copies the item here", fm.fileExists(atPath: work.appending(path: "Notes.txt").path))
        check("Copy keeps the original", fm.fileExists(atPath: notes.path))
        check("a copy shows in the list", model.tab.items.contains { $0.name == "Notes.txt" })

        // S-011 Cut and paste to move
        let moveMe = work.appending(path: "Move me.txt")
        try? Data("m".utf8).write(to: moveMe)
        model.tab.go(to: docs)
        model.tab.go(to: work)
        await settle()
        model.tab.selection = [moveMe]
        model.actions.cutSelection()
        check("Cut leaves the item in place", fm.fileExists(atPath: moveMe.path) && model.actions.isCut(moveMe))
        model.tab.go(to: docs)
        await settle()
        check("Cut items stay until paste", fm.fileExists(atPath: moveMe.path))
        model.actions.paste()
        await settle()
        check("Paste moves the item", fm.fileExists(atPath: docs.appending(path: "Move me.txt").path) && !fm.fileExists(atPath: moveMe.path))
        check("Paste clears the cut", !model.actions.isCut(moveMe))
        let again = docs.appending(path: "Move me.txt")
        model.tab.selection = [again]
        model.actions.cutSelection()
        model.actions.clearCut()
        check("Escape clears the cut", !model.actions.isCut(again))
        model.tab.selection = [again]
        model.actions.cutSelection()
        model.tab.selection = [docs.appending(path: "Notes.txt")]
        model.actions.copySelection()
        check("Copying something else clears the cut", !model.actions.isCut(again))

        // S-012 Resolve name conflicts
                    try? fm.createDirectory(at: drop, withIntermediateDirectories: true)
        try? Data("old".utf8).write(to: drop.appending(path: "Notes.txt"))
        try? Data("old".utf8).write(to: drop.appending(path: "file2.txt"))
        model.tab.go(to: docs)
        await settle()
        model.tab.selection = [docs.appending(path: "Notes.txt")]
        model.actions.copySelection()
        model.tab.go(to: drop)
        model.actions.paste()
        await Wait.until { model.actions.pendingConflict != nil }
        check("a name conflict asks first", model.actions.pendingConflict != nil)
        model.actions.resolveConflict(.skip, applyToAll: false)
        await settle()
        check("Skip leaves the existing file untouched",
              (try? String(contentsOf: drop.appending(path: "Notes.txt"), encoding: .utf8)) == "old")
        model.tab.go(to: docs)
        await settle()
        model.tab.selection = [docs.appending(path: "Notes.txt"), docs.appending(path: "file2.txt")]
        model.actions.copySelection()
        model.tab.go(to: drop)
        model.actions.paste()
        await Wait.until { model.actions.pendingConflict != nil }
        model.actions.resolveConflict(.keepBoth, applyToAll: true)
        await settle()
        check("Do this for all asks once", model.actions.pendingConflict == nil)
        check("Keep Both adds a numbered copy",
              fm.fileExists(atPath: drop.appending(path: "Notes (2).txt").path)
              && fm.fileExists(atPath: drop.appending(path: "file2 (2).txt").path))

        // S-013 Move to Trash
        let trashDir = home.appending(path: ".Trash", directoryHint: .isDirectory)
        for n in ["a.txt", "b.txt", "c.txt"] { try? Data(n.utf8).write(to: drop.appending(path: "gone-\(n)")) }
        model.tab.go(to: drop)
        await settle()
        let firstGone = model.tab.items.firstIndex { $0.name == "gone-b.txt" } ?? 0
        // Select from the listing, as a click does: listed URLs can spell /tmp as /private/tmp.
        @MainActor func pick(_ names: String...) { model.tab.selection = Set(model.tab.items.filter { names.contains($0.name) }.map(\.url)) }
        pick("gone-b.txt")
        model.actions.trashSelection()
        await settle()
        check("Move to Trash removes the item from the folder", !fm.fileExists(atPath: drop.appending(path: "gone-b.txt").path))
        check("the item is in the Trash", fm.fileExists(atPath: trashDir.appending(path: "gone-b.txt").path))
        check("selection moves to the next item", model.tab.selection == [model.tab.items[min(firstGone, model.tab.items.count - 1)].url], "selection \(model.tab.selection) items \(model.tab.items.map(\.name)) first \(firstGone)")
        pick("gone-a.txt")
        model.actions.askDeleteImmediately()
        check("Delete Immediately asks first", model.actions.pendingDelete != nil && fm.fileExists(atPath: drop.appending(path: "gone-a.txt").path))
        model.actions.deleteImmediately()
        await settle()
        check("Delete Immediately removes the item for good",
              !fm.fileExists(atPath: drop.appending(path: "gone-a.txt").path) && !fm.fileExists(atPath: trashDir.appending(path: "gone-a.txt").path))

        // S-014 Undo file operations
        let um = model.actions.undoManager
        for n in ["u1.txt", "u2.txt"] { try? Data(n.utf8).write(to: drop.appending(path: n)) }
        model.tab.go(to: docs)
        model.tab.go(to: drop)
        await settle()
        pick("u1.txt")
        model.actions.trashSelection()
        await settle()
        check("Edit > Undo names the action", um.undoMenuItemTitle == "Undo Move to Trash", um.undoMenuItemTitle)
        um.undo()
        await settle()
        check("Undo of Trash restores the original path", fm.fileExists(atPath: drop.appending(path: "u1.txt").path))
        check("Edit > Redo names the action", um.redoMenuItemTitle == "Redo Move to Trash", um.redoMenuItemTitle)
        um.redo()
        await settle()
        check("Redo moves it to the Trash again", !fm.fileExists(atPath: drop.appending(path: "u1.txt").path))
        um.undo()
        await settle()
        check("Undo works again after Redo", fm.fileExists(atPath: drop.appending(path: "u1.txt").path))
        pick("u2.txt")
        model.actions.cutSelection()
        model.tab.go(to: work)
        await settle()
        model.actions.paste()
        await settle()
        check("a move registers an undo named for the move", um.undoMenuItemTitle.hasPrefix("Undo Move"), um.undoMenuItemTitle)
        um.undo()
        await settle()
        check("Undo of a move puts the item back", fm.fileExists(atPath: drop.appending(path: "u2.txt").path) && !fm.fileExists(atPath: work.appending(path: "u2.txt").path))

        // S-015 Rename and S-016 New folder
        model.tab.go(to: docs)
        model.tab.go(to: drop)
        await settle()
        model.actions.newFolder()
        await settle()
        check("New Folder makes \"New folder\"", fm.fileExists(atPath: drop.appending(path: "New folder").path))
        check("the new folder is selected and being named", model.actions.renamingURL?.lastPathComponent == "New folder", "\(String(describing: model.actions.renamingURL))")
        model.actions.renameText = "Reports"
        model.actions.commitRename()
        await settle()
        check("Return in the name field renames", fm.fileExists(atPath: drop.appending(path: "Reports").path) && !fm.fileExists(atPath: drop.appending(path: "New folder").path))
        check("the renamed item is selected", model.tab.selectedItems.first?.name == "Reports", "\(model.tab.selectedItems.map(\.name))")
        check("Edit > Undo names the rename", um.undoMenuItemTitle == "Undo Rename", um.undoMenuItemTitle)
        um.undo()
        await settle()
        check("Undo of a rename restores the old name", fm.fileExists(atPath: drop.appending(path: "New folder").path))
        pick("Notes.txt")
        model.actions.beginRename()
        check("Rename starts on a single selection", model.actions.renamingURL != nil)
        model.actions.renameText = "file2.txt"
        model.actions.commitRename()
        await settle()
        check("a taken name shows an error and keeps editing", model.actions.renameError != nil && model.actions.renamingURL != nil, model.actions.renameError ?? "nil")
        model.actions.renameText = "  "
        model.actions.commitRename()
        await settle()
        check("an empty name shows an error", model.actions.renameError == "Give the item a name.", model.actions.renameError ?? "nil")
        model.actions.cancelRename()
        check("Escape stops renaming", model.actions.renamingURL == nil)

        // S-017 Drag files with Windows rules
        let dest = drop.appending(path: "Dest", directoryHint: .isDirectory)
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for n in ["d1.txt", "d2.txt", "d3.txt"] { try? Data(n.utf8).write(to: drop.appending(path: n)) }
        model.tab.go(to: docs)
        model.tab.go(to: drop)
        await settle()
        @MainActor func listed(_ name: String) -> URL { model.tab.items.first { $0.name == name }!.url }
        model.actions.dragStarted([listed("d3.txt")])
        check("a drag inside one volume moves", model.actions.dropMode(into: dest) == .move)
        model.actions.dragStarted([])
        check("a drag from another app copies until it lands", model.actions.dropMode(into: dest) == .copy)
        model.actions.drop([listed("d1.txt")], into: dest, option: false, command: false)
        await settle()
        check("dropping with no key moves on the same volume",
              fm.fileExists(atPath: dest.appending(path: "d1.txt").path) && !fm.fileExists(atPath: drop.appending(path: "d1.txt").path))
        model.actions.drop([listed("d2.txt")], into: dest, option: true, command: false)
        await settle()
        check("dropping with Option copies",
              fm.fileExists(atPath: dest.appending(path: "d2.txt").path) && fm.fileExists(atPath: drop.appending(path: "d2.txt").path))
        model.actions.drop([dest], into: dest, option: false, command: false)
        await settle()
        check("a folder dropped on itself is refused with a message", model.actions.alertMessage?.contains("cannot go inside itself") == true, model.actions.alertMessage ?? "nil")
        model.actions.alertMessage = nil
        check("a drop registers an undo", um.undoMenuItemTitle.hasPrefix("Undo Copy") || um.undoMenuItemTitle.hasPrefix("Undo Move"), um.undoMenuItemTitle)
    }
}
