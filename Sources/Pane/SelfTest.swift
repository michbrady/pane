import AppKit
import PaneKit

/// Self-test for agents: runs the app's real functions on a throwaway home
/// folder, prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_HOME=/tmp/Pane-self-home ~/Applications/Pane.app/Contents/MacOS/Pane --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Locations.isOverridden, Locations.home.path.hasPrefix("/tmp/") || Locations.home.path.hasPrefix("/private/tmp/") else {
            print("SELFTEST refused: set APP_HOME to a folder in /tmp")
            finish(code: 1)
            return
        }
        Task {
            let home = Locations.home
            let fm = FileManager.default
            let work = home.appending(path: "Documents/Work", directoryHint: .isDirectory)
            let docs = home.appending(path: "Documents", directoryHint: .isDirectory)
            try? fm.createDirectory(at: work, withIntermediateDirectories: true)
            try? Data("hello".utf8).write(to: docs.appending(path: "Notes.txt"))
            try? Data("x".utf8).write(to: docs.appending(path: "file10.txt"))
            try? Data("x".utf8).write(to: docs.appending(path: "file2.txt"))

            model.go(to: docs)
            try? await Task.sleep(for: .seconds(0.5))
            check("a folder lists its items", model.items.count >= 4, "\(model.items.count) items")
            check("folders come first", model.items.first?.isFolder == true)
            let names = model.items.map(\.name)
            check("names sort naturally", (names.firstIndex(of: "file2.txt") ?? 0) < (names.firstIndex(of: "file10.txt") ?? 0))

            model.open([work])
            try? await Task.sleep(for: .seconds(0.3))
            check("open on a folder shows its contents", model.currentFolder.path == work.standardizedFileURL.path)
            check("Back is available", model.canGoBack)
            model.goUp()
            check("Go up shows the parent", model.currentFolder.path == docs.standardizedFileURL.path)
            model.goBack()
            check("Go back returns to the last folder", model.currentFolder.path == work.standardizedFileURL.path)
            model.goForward()
            check("Go forward returns", model.currentFolder.path == docs.standardizedFileURL.path)

            model.beginEditingAddress()
            check("the address field shows ~ paths", model.addressText == "~/Documents", model.addressText)
            model.addressText = "~/Documents/Work"
            model.commitAddress()
            try? await Task.sleep(for: .seconds(0.2))
            check("a typed path goes there", model.currentFolder.path == work.standardizedFileURL.path)
            model.beginEditingAddress()
            model.addressText = "~/Nope"
            model.commitAddress()
            check("a bad path shows an error and stays", model.addressError != nil && model.isEditingAddress)
            model.cancelEditingAddress()
            check("Escape restores the breadcrumbs", !model.isEditingAddress)

            check("the tree follows the current folder", model.navSelection == "home:" + work.standardizedFileURL.path, model.navSelection ?? "nil")
            check("the tree opens the folders above", model.expanded.contains("home:" + docs.standardizedFileURL.path))

            try? Data("new".utf8).write(to: work.appending(path: "Added.txt"))
            try? await Task.sleep(for: .seconds(2))
            check("a file added from outside appears", model.items.contains { $0.name == "Added.txt" })

            // S-010 Copy and paste
            model.go(to: docs)
            try? await Task.sleep(for: .seconds(0.3))
            let notes = docs.appending(path: "Notes.txt")
            model.selection = [notes]
            model.copySelection()
            model.go(to: work)
            model.paste()
            try? await Task.sleep(for: .seconds(1))
            check("Paste copies the item here", fm.fileExists(atPath: work.appending(path: "Notes.txt").path))
            check("Copy keeps the original", fm.fileExists(atPath: notes.path))
            check("a copy shows in the list", model.items.contains { $0.name == "Notes.txt" })

            // S-011 Cut and paste to move
            let moveMe = work.appending(path: "Move me.txt")
            try? Data("m".utf8).write(to: moveMe)
            model.go(to: docs)
            model.go(to: work)
            try? await Task.sleep(for: .seconds(0.4))
            model.selection = [moveMe]
            model.cutSelection()
            check("Cut leaves the item in place", fm.fileExists(atPath: moveMe.path) && model.isCut(moveMe))
            model.go(to: docs)
            try? await Task.sleep(for: .seconds(0.3))
            check("Cut items stay until paste", fm.fileExists(atPath: moveMe.path))
            model.paste()
            try? await Task.sleep(for: .seconds(1))
            check("Paste moves the item", fm.fileExists(atPath: docs.appending(path: "Move me.txt").path) && !fm.fileExists(atPath: moveMe.path))
            check("Paste clears the cut", !model.isCut(moveMe))
            let again = docs.appending(path: "Move me.txt")
            model.selection = [again]
            model.cutSelection()
            model.clearCut()
            check("Escape clears the cut", !model.isCut(again))
            model.selection = [again]
            model.cutSelection()
            model.selection = [docs.appending(path: "Notes.txt")]
            model.copySelection()
            check("Copying something else clears the cut", !model.isCut(again))

            // S-012 Resolve name conflicts
            let drop = home.appending(path: "Conflicts", directoryHint: .isDirectory)
            try? fm.createDirectory(at: drop, withIntermediateDirectories: true)
            try? Data("old".utf8).write(to: drop.appending(path: "Notes.txt"))
            try? Data("old".utf8).write(to: drop.appending(path: "file2.txt"))
            model.go(to: docs)
            try? await Task.sleep(for: .seconds(0.3))
            model.selection = [docs.appending(path: "Notes.txt")]
            model.copySelection()
            model.go(to: drop)
            model.paste()
            try? await Task.sleep(for: .seconds(0.5))
            check("a name conflict asks first", model.pendingConflict != nil)
            model.resolveConflict(.skip, applyToAll: false)
            try? await Task.sleep(for: .seconds(0.5))
            check("Skip leaves the existing file untouched",
                  (try? String(contentsOf: drop.appending(path: "Notes.txt"), encoding: .utf8)) == "old")
            model.go(to: docs)
            try? await Task.sleep(for: .seconds(0.3))
            model.selection = [docs.appending(path: "Notes.txt"), docs.appending(path: "file2.txt")]
            model.copySelection()
            model.go(to: drop)
            model.paste()
            try? await Task.sleep(for: .seconds(0.5))
            model.resolveConflict(.keepBoth, applyToAll: true)
            try? await Task.sleep(for: .seconds(0.8))
            check("Do this for all asks once", model.pendingConflict == nil)
            check("Keep Both adds a numbered copy",
                  fm.fileExists(atPath: drop.appending(path: "Notes (2).txt").path)
                  && fm.fileExists(atPath: drop.appending(path: "file2 (2).txt").path))

            // S-013 Move to Trash
            let trashDir = home.appending(path: ".Trash", directoryHint: .isDirectory)
            for n in ["a.txt", "b.txt", "c.txt"] { try? Data(n.utf8).write(to: drop.appending(path: "gone-\(n)")) }
            model.go(to: drop)
            try? await Task.sleep(for: .seconds(0.4))
            let firstGone = model.items.firstIndex { $0.name == "gone-b.txt" } ?? 0
            // Select from the listing, as a click does: listed URLs can spell /tmp as /private/tmp.
            @MainActor func pick(_ names: String...) { model.selection = Set(model.items.filter { names.contains($0.name) }.map(\.url)) }
            pick("gone-b.txt")
            model.trashSelection()
            try? await Task.sleep(for: .seconds(1))
            check("Move to Trash removes the item from the folder", !fm.fileExists(atPath: drop.appending(path: "gone-b.txt").path))
            check("the item is in the Trash", fm.fileExists(atPath: trashDir.appending(path: "gone-b.txt").path))
            check("selection moves to the next item", model.selection == [model.items[min(firstGone, model.items.count - 1)].url], "selection \(model.selection) items \(model.items.map(\.name)) first \(firstGone)")
            pick("gone-a.txt")
            model.askDeleteImmediately()
            check("Delete Immediately asks first", model.pendingDelete != nil && fm.fileExists(atPath: drop.appending(path: "gone-a.txt").path))
            model.deleteImmediately()
            try? await Task.sleep(for: .seconds(1))
            check("Delete Immediately removes the item for good",
                  !fm.fileExists(atPath: drop.appending(path: "gone-a.txt").path) && !fm.fileExists(atPath: trashDir.appending(path: "gone-a.txt").path))

            // S-014 Undo file operations
            let um = model.undoManager
            for n in ["u1.txt", "u2.txt"] { try? Data(n.utf8).write(to: drop.appending(path: n)) }
            model.go(to: docs)
            model.go(to: drop)
            try? await Task.sleep(for: .seconds(0.5))
            pick("u1.txt")
            model.trashSelection()
            try? await Task.sleep(for: .seconds(1))
            check("Edit > Undo names the action", um.undoMenuItemTitle == "Undo Move to Trash", um.undoMenuItemTitle)
            um.undo()
            try? await Task.sleep(for: .seconds(1))
            check("Undo of Trash restores the original path", fm.fileExists(atPath: drop.appending(path: "u1.txt").path))
            check("Edit > Redo names the action", um.redoMenuItemTitle == "Redo Move to Trash", um.redoMenuItemTitle)
            um.redo()
            try? await Task.sleep(for: .seconds(1))
            check("Redo moves it to the Trash again", !fm.fileExists(atPath: drop.appending(path: "u1.txt").path))
            um.undo()
            try? await Task.sleep(for: .seconds(1))
            check("Undo works again after Redo", fm.fileExists(atPath: drop.appending(path: "u1.txt").path))
            pick("u2.txt")
            model.cutSelection()
            model.go(to: work)
            try? await Task.sleep(for: .seconds(0.3))
            model.paste()
            try? await Task.sleep(for: .seconds(1))
            check("a move registers an undo named for the move", um.undoMenuItemTitle.hasPrefix("Undo Move"), um.undoMenuItemTitle)
            um.undo()
            try? await Task.sleep(for: .seconds(1))
            check("Undo of a move puts the item back", fm.fileExists(atPath: drop.appending(path: "u2.txt").path) && !fm.fileExists(atPath: work.appending(path: "u2.txt").path))

            // S-015 Rename and S-016 New folder
            model.go(to: docs)
            model.go(to: drop)
            try? await Task.sleep(for: .seconds(0.5))
            model.newFolder()
            try? await Task.sleep(for: .seconds(1))
            check("New Folder makes \"New folder\"", fm.fileExists(atPath: drop.appending(path: "New folder").path))
            check("the new folder is selected and being named", model.renamingURL?.lastPathComponent == "New folder", "\(String(describing: model.renamingURL))")
            model.renameText = "Reports"
            model.commitRename()
            try? await Task.sleep(for: .seconds(1))
            check("Return in the name field renames", fm.fileExists(atPath: drop.appending(path: "Reports").path) && !fm.fileExists(atPath: drop.appending(path: "New folder").path))
            check("the renamed item is selected", model.selectedItems.first?.name == "Reports", "\(model.selectedItems.map(\.name))")
            check("Edit > Undo names the rename", um.undoMenuItemTitle == "Undo Rename", um.undoMenuItemTitle)
            um.undo()
            try? await Task.sleep(for: .seconds(1))
            check("Undo of a rename restores the old name", fm.fileExists(atPath: drop.appending(path: "New folder").path))
            pick("Notes.txt")
            model.beginRename()
            check("Rename starts on a single selection", model.renamingURL != nil)
            model.renameText = "file2.txt"
            model.commitRename()
            try? await Task.sleep(for: .seconds(0.5))
            check("a taken name shows an error and keeps editing", model.renameError != nil && model.renamingURL != nil, model.renameError ?? "nil")
            model.renameText = "  "
            model.commitRename()
            try? await Task.sleep(for: .seconds(0.5))
            check("an empty name shows an error", model.renameError == "Give the item a name.", model.renameError ?? "nil")
            model.cancelRename()
            check("Escape stops renaming", model.renamingURL == nil)

            // S-017 Drag files with Windows rules
            let dest = drop.appending(path: "Dest", directoryHint: .isDirectory)
            try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for n in ["d1.txt", "d2.txt", "d3.txt"] { try? Data(n.utf8).write(to: drop.appending(path: n)) }
            model.go(to: docs)
            model.go(to: drop)
            try? await Task.sleep(for: .seconds(0.5))
            @MainActor func listed(_ name: String) -> URL { model.items.first { $0.name == name }!.url }
            model.dragStarted([listed("d3.txt")])
            check("a drag inside one volume moves", model.dropMode(into: dest) == .move)
            model.dragStarted([])
            check("a drag from another app copies until it lands", model.dropMode(into: dest) == .copy)
            model.drop([listed("d1.txt")], into: dest, option: false, command: false)
            try? await Task.sleep(for: .seconds(1))
            check("dropping with no key moves on the same volume",
                  fm.fileExists(atPath: dest.appending(path: "d1.txt").path) && !fm.fileExists(atPath: drop.appending(path: "d1.txt").path))
            model.drop([listed("d2.txt")], into: dest, option: true, command: false)
            try? await Task.sleep(for: .seconds(1))
            check("dropping with Option copies",
                  fm.fileExists(atPath: dest.appending(path: "d2.txt").path) && fm.fileExists(atPath: drop.appending(path: "d2.txt").path))
            model.drop([dest], into: dest, option: false, command: false)
            try? await Task.sleep(for: .seconds(1))
            check("a folder dropped on itself is refused with a message", model.alertMessage?.contains("cannot go inside itself") == true, model.alertMessage ?? "nil")
            model.alertMessage = nil
            check("a drop registers an undo", um.undoMenuItemTitle.hasPrefix("Undo Copy") || um.undoMenuItemTitle.hasPrefix("Undo Move"), um.undoMenuItemTitle)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
