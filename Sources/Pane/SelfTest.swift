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

            model.tab.go(to: docs)
            try? await Task.sleep(for: .seconds(0.5))
            check("a folder lists its items", model.tab.items.count >= 4, "\(model.tab.items.count) items")
            check("folders come first", model.tab.items.first?.isFolder == true)
            let names = model.tab.items.map(\.name)
            check("names sort naturally", (names.firstIndex(of: "file2.txt") ?? 0) < (names.firstIndex(of: "file10.txt") ?? 0))

            model.tab.open([work])
            try? await Task.sleep(for: .seconds(0.3))
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
            try? await Task.sleep(for: .seconds(0.2))
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
            try? await Task.sleep(for: .seconds(2))
            check("a file added from outside appears", model.tab.items.contains { $0.name == "Added.txt" })

            // S-010 Copy and paste
            model.tab.go(to: docs)
            try? await Task.sleep(for: .seconds(0.3))
            let notes = docs.appending(path: "Notes.txt")
            model.tab.selection = [notes]
            model.actions.copySelection()
            model.tab.go(to: work)
            model.actions.paste()
            try? await Task.sleep(for: .seconds(1))
            check("Paste copies the item here", fm.fileExists(atPath: work.appending(path: "Notes.txt").path))
            check("Copy keeps the original", fm.fileExists(atPath: notes.path))
            check("a copy shows in the list", model.tab.items.contains { $0.name == "Notes.txt" })

            // S-011 Cut and paste to move
            let moveMe = work.appending(path: "Move me.txt")
            try? Data("m".utf8).write(to: moveMe)
            model.tab.go(to: docs)
            model.tab.go(to: work)
            try? await Task.sleep(for: .seconds(0.4))
            model.tab.selection = [moveMe]
            model.actions.cutSelection()
            check("Cut leaves the item in place", fm.fileExists(atPath: moveMe.path) && model.actions.isCut(moveMe))
            model.tab.go(to: docs)
            try? await Task.sleep(for: .seconds(0.3))
            check("Cut items stay until paste", fm.fileExists(atPath: moveMe.path))
            model.actions.paste()
            try? await Task.sleep(for: .seconds(1))
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
            let drop = home.appending(path: "Conflicts", directoryHint: .isDirectory)
            try? fm.createDirectory(at: drop, withIntermediateDirectories: true)
            try? Data("old".utf8).write(to: drop.appending(path: "Notes.txt"))
            try? Data("old".utf8).write(to: drop.appending(path: "file2.txt"))
            model.tab.go(to: docs)
            try? await Task.sleep(for: .seconds(0.3))
            model.tab.selection = [docs.appending(path: "Notes.txt")]
            model.actions.copySelection()
            model.tab.go(to: drop)
            model.actions.paste()
            try? await Task.sleep(for: .seconds(0.5))
            check("a name conflict asks first", model.actions.pendingConflict != nil)
            model.actions.resolveConflict(.skip, applyToAll: false)
            try? await Task.sleep(for: .seconds(0.5))
            check("Skip leaves the existing file untouched",
                  (try? String(contentsOf: drop.appending(path: "Notes.txt"), encoding: .utf8)) == "old")
            model.tab.go(to: docs)
            try? await Task.sleep(for: .seconds(0.3))
            model.tab.selection = [docs.appending(path: "Notes.txt"), docs.appending(path: "file2.txt")]
            model.actions.copySelection()
            model.tab.go(to: drop)
            model.actions.paste()
            try? await Task.sleep(for: .seconds(0.5))
            model.actions.resolveConflict(.keepBoth, applyToAll: true)
            try? await Task.sleep(for: .seconds(0.8))
            check("Do this for all asks once", model.actions.pendingConflict == nil)
            check("Keep Both adds a numbered copy",
                  fm.fileExists(atPath: drop.appending(path: "Notes (2).txt").path)
                  && fm.fileExists(atPath: drop.appending(path: "file2 (2).txt").path))

            // S-013 Move to Trash
            let trashDir = home.appending(path: ".Trash", directoryHint: .isDirectory)
            for n in ["a.txt", "b.txt", "c.txt"] { try? Data(n.utf8).write(to: drop.appending(path: "gone-\(n)")) }
            model.tab.go(to: drop)
            try? await Task.sleep(for: .seconds(0.4))
            let firstGone = model.tab.items.firstIndex { $0.name == "gone-b.txt" } ?? 0
            // Select from the listing, as a click does: listed URLs can spell /tmp as /private/tmp.
            @MainActor func pick(_ names: String...) { model.tab.selection = Set(model.tab.items.filter { names.contains($0.name) }.map(\.url)) }
            pick("gone-b.txt")
            model.actions.trashSelection()
            try? await Task.sleep(for: .seconds(1))
            check("Move to Trash removes the item from the folder", !fm.fileExists(atPath: drop.appending(path: "gone-b.txt").path))
            check("the item is in the Trash", fm.fileExists(atPath: trashDir.appending(path: "gone-b.txt").path))
            check("selection moves to the next item", model.tab.selection == [model.tab.items[min(firstGone, model.tab.items.count - 1)].url], "selection \(model.tab.selection) items \(model.tab.items.map(\.name)) first \(firstGone)")
            pick("gone-a.txt")
            model.actions.askDeleteImmediately()
            check("Delete Immediately asks first", model.actions.pendingDelete != nil && fm.fileExists(atPath: drop.appending(path: "gone-a.txt").path))
            model.actions.deleteImmediately()
            try? await Task.sleep(for: .seconds(1))
            check("Delete Immediately removes the item for good",
                  !fm.fileExists(atPath: drop.appending(path: "gone-a.txt").path) && !fm.fileExists(atPath: trashDir.appending(path: "gone-a.txt").path))

            // S-014 Undo file operations
            let um = model.actions.undoManager
            for n in ["u1.txt", "u2.txt"] { try? Data(n.utf8).write(to: drop.appending(path: n)) }
            model.tab.go(to: docs)
            model.tab.go(to: drop)
            try? await Task.sleep(for: .seconds(0.5))
            pick("u1.txt")
            model.actions.trashSelection()
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
            model.actions.cutSelection()
            model.tab.go(to: work)
            try? await Task.sleep(for: .seconds(0.3))
            model.actions.paste()
            try? await Task.sleep(for: .seconds(1))
            check("a move registers an undo named for the move", um.undoMenuItemTitle.hasPrefix("Undo Move"), um.undoMenuItemTitle)
            um.undo()
            try? await Task.sleep(for: .seconds(1))
            check("Undo of a move puts the item back", fm.fileExists(atPath: drop.appending(path: "u2.txt").path) && !fm.fileExists(atPath: work.appending(path: "u2.txt").path))

            // S-015 Rename and S-016 New folder
            model.tab.go(to: docs)
            model.tab.go(to: drop)
            try? await Task.sleep(for: .seconds(0.5))
            model.actions.newFolder()
            try? await Task.sleep(for: .seconds(1))
            check("New Folder makes \"New folder\"", fm.fileExists(atPath: drop.appending(path: "New folder").path))
            check("the new folder is selected and being named", model.actions.renamingURL?.lastPathComponent == "New folder", "\(String(describing: model.actions.renamingURL))")
            model.actions.renameText = "Reports"
            model.actions.commitRename()
            try? await Task.sleep(for: .seconds(1))
            check("Return in the name field renames", fm.fileExists(atPath: drop.appending(path: "Reports").path) && !fm.fileExists(atPath: drop.appending(path: "New folder").path))
            check("the renamed item is selected", model.tab.selectedItems.first?.name == "Reports", "\(model.tab.selectedItems.map(\.name))")
            check("Edit > Undo names the rename", um.undoMenuItemTitle == "Undo Rename", um.undoMenuItemTitle)
            um.undo()
            try? await Task.sleep(for: .seconds(1))
            check("Undo of a rename restores the old name", fm.fileExists(atPath: drop.appending(path: "New folder").path))
            pick("Notes.txt")
            model.actions.beginRename()
            check("Rename starts on a single selection", model.actions.renamingURL != nil)
            model.actions.renameText = "file2.txt"
            model.actions.commitRename()
            try? await Task.sleep(for: .seconds(0.5))
            check("a taken name shows an error and keeps editing", model.actions.renameError != nil && model.actions.renamingURL != nil, model.actions.renameError ?? "nil")
            model.actions.renameText = "  "
            model.actions.commitRename()
            try? await Task.sleep(for: .seconds(0.5))
            check("an empty name shows an error", model.actions.renameError == "Give the item a name.", model.actions.renameError ?? "nil")
            model.actions.cancelRename()
            check("Escape stops renaming", model.actions.renamingURL == nil)

            // S-017 Drag files with Windows rules
            let dest = drop.appending(path: "Dest", directoryHint: .isDirectory)
            try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for n in ["d1.txt", "d2.txt", "d3.txt"] { try? Data(n.utf8).write(to: drop.appending(path: n)) }
            model.tab.go(to: docs)
            model.tab.go(to: drop)
            try? await Task.sleep(for: .seconds(0.5))
            @MainActor func listed(_ name: String) -> URL { model.tab.items.first { $0.name == name }!.url }
            model.actions.dragStarted([listed("d3.txt")])
            check("a drag inside one volume moves", model.actions.dropMode(into: dest) == .move)
            model.actions.dragStarted([])
            check("a drag from another app copies until it lands", model.actions.dropMode(into: dest) == .copy)
            model.actions.drop([listed("d1.txt")], into: dest, option: false, command: false)
            try? await Task.sleep(for: .seconds(1))
            check("dropping with no key moves on the same volume",
                  fm.fileExists(atPath: dest.appending(path: "d1.txt").path) && !fm.fileExists(atPath: drop.appending(path: "d1.txt").path))
            model.actions.drop([listed("d2.txt")], into: dest, option: true, command: false)
            try? await Task.sleep(for: .seconds(1))
            check("dropping with Option copies",
                  fm.fileExists(atPath: dest.appending(path: "d2.txt").path) && fm.fileExists(atPath: drop.appending(path: "d2.txt").path))
            model.actions.drop([dest], into: dest, option: false, command: false)
            try? await Task.sleep(for: .seconds(1))
            check("a folder dropped on itself is refused with a message", model.actions.alertMessage?.contains("cannot go inside itself") == true, model.actions.alertMessage ?? "nil")
            model.actions.alertMessage = nil
            check("a drop registers an undo", um.undoMenuItemTitle.hasPrefix("Undo Copy") || um.undoMenuItemTitle.hasPrefix("Undo Move"), um.undoMenuItemTitle)

            // S-020 Sort by column and S-021 Folders first
            model.tab.go(to: docs)
            try? await Task.sleep(for: .seconds(0.5))
            model.view.setSort(.size, ascending: false)
            let files = model.tab.items.filter { !$0.isFolder }
            check("sorting by size puts the largest file first", files.first?.name == "Trip itinerary.pdf", files.first?.name ?? "nil")
            check("Size sorts by bytes, not text", zip(files, files.dropFirst()).allSatisfy { ($0.size ?? 0) >= ($1.size ?? 0) })
            check("folders stay first while sorting", model.tab.items.first?.isFolder == true)
            model.view.foldersFirst = false
            check("folders move into the order when folders first is off", model.tab.items.last?.isFolder == true, model.tab.items.last?.name ?? "nil")
            model.view.foldersFirst = true
            model.view.setSort(.name, ascending: false)
            check("a second click reverses the order", model.tab.items.first(where: { !$0.isFolder })?.name == "Trip itinerary.pdf")
            check("the sort is saved", ViewSettings().sortKey == .name && ViewSettings().ascending == false)
            model.view.reset()

            // S-024 Show extensions and hidden files
            try? Data("s".utf8).write(to: drop.appending(path: ".secret"))
            model.tab.go(to: docs)
            model.tab.go(to: drop)
            try? await Task.sleep(for: .seconds(0.6))
            check("hidden items are off by default", !model.tab.items.contains { $0.name == ".secret" })
            model.view.showHidden = true
            try? await Task.sleep(for: .seconds(0.8))
            check("Show Hidden Items lists dotfiles", model.tab.items.contains { $0.name == ".secret" })
            model.view.showHidden = false
            try? await Task.sleep(for: .seconds(0.8))
            check("turning it off hides them again", !model.tab.items.contains { $0.name == ".secret" })
            model.view.showExtensions = false
            check("Show File Extensions off drops the extension from the shown name",
                  model.tab.items.first { $0.name == "Notes.txt" }?.displayName(showExtensions: model.view.showExtensions) == "Notes")
            check("the settings are saved", ViewSettings().showExtensions == false)
            model.view.reset()

            // S-025 Pin folders to Quick access
            check("Desktop, Downloads, Documents, and Pictures are pinned at first",
                  model.quickRoots.map(\.name) == ["Desktop", "Downloads", "Documents", "Pictures"], "\(model.quickRoots.map(\.name))")
            let pinned = home.appending(path: "Projects", directoryHint: .isDirectory)
            try? fm.createDirectory(at: pinned, withIntermediateDirectories: true)
            model.pin(pinned)
            check("Pin adds a Quick access row", model.quickRoots.last?.name == "Projects" && model.isPinned(pinned))
            check("pinning twice adds one row", { model.pin(pinned); return model.quickRoots.filter { $0.name == "Projects" }.count == 1 }())
            let moved = home.appending(path: "Work 2", directoryHint: .isDirectory)
            try? fm.moveItem(at: pinned, to: moved)
            model.tab.go(to: docs)
            model.tab.go(to: drop)
            try? await Task.sleep(for: .seconds(0.4))
            check("a pinned folder that was renamed still shows, under its new name", model.quickRoots.last?.name == "Work 2", "\(model.quickRoots.map(\.name))")
            model.unpin(moved)
            check("Unpin removes the row", !model.quickRoots.contains { $0.name == "Work 2" })
            check("pins are saved", Prefs.defaults.array(forKey: "pane.pins") != nil)

            // S-026 Tabs and S-027 Open a folder in a new tab
            model.tab.go(to: docs)
            try? await Task.sleep(for: .seconds(0.4))
            let first = model.tab
            check("Pane starts with one tab", model.tabs.count == 1)
            first.selection = Set(first.items.prefix(1).map(\.url))
            model.newTab(at: drop)
            try? await Task.sleep(for: .seconds(0.6))
            check("New Tab opens a second tab and shows it", model.tabs.count == 2 && model.activeIndex == 1)
            check("the new tab shows the folder asked for", model.tab.currentFolder.path == drop.standardizedFileURL.path)
            check("a tab keeps its own folder", first.currentFolder.path == docs.standardizedFileURL.path)
            check("a tab keeps its own selection", model.tab.selection.isEmpty && !first.selection.isEmpty)
            model.select(0)
            check("selecting a tab shows it", model.tab === first && model.navSelection?.hasSuffix(docs.standardizedFileURL.path) == true, model.navSelection ?? "nil")
            model.selectNextTab()
            check("Show Next Tab moves on", model.activeIndex == 1)
            model.selectNextTab()
            check("Show Next Tab wraps around", model.activeIndex == 0)
            model.selectPreviousTab()
            check("Show Previous Tab wraps back", model.activeIndex == 1)
            model.select(7)
            check("a tab number that does not exist is ignored", model.activeIndex == 1)
            check("the open tabs are saved", Prefs.defaults.stringArray(forKey: "pane.tabs")?.count == 2)
            model.select(0)
            model.newTab(at: work, activate: false)
            check("a tab opened in the background does not take over", model.tabs.count == 3 && model.tab === first)
            model.close(model.tabs[2])
            check("Close Tab removes a tab", model.tabs.count == 2)
            model.select(1)
            model.close(model.tab)
            check("closing the shown tab shows a neighbor", model.tabs.count == 1 && model.activeIndex == 0)
            check("the last tab is not closed by Close Tab", model.close(model.tab) == false && model.tabs.count == 1)
            model.newTab(at: work)
            model.closeOtherTabs(except: model.tab)
            check("Close Other Tabs keeps one", model.tabs.count == 1 && model.tab.currentFolder.path == work.standardizedFileURL.path)
            model.tab.go(to: docs)
            try? await Task.sleep(for: .seconds(0.3))

            // S-023 Switch view mode
            check("Details is the first view", model.view.mode == .details)
            model.view.mode = .icons
            check("the view mode is saved", ViewSettings().mode == .icons)
            check("each mode has a name and an icon", ViewMode.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
            model.tab.selection = Set(model.tab.items.prefix(1).map(\.url))
            model.view.mode = .list
            check("switching the view keeps the selection", model.tab.selection.count == 1)
            model.view.reset()
            check("reset returns to Details", model.view.mode == .details)

            // S-022 Choose and resize columns
            model.tab.go(to: docs)
            try? await Task.sleep(for: .seconds(0.4))
            check("Date created and Tags start hidden",
                  model.view.columns(for: docs)[visibility: "created"] != .visible && model.view.columns(for: docs)[visibility: "tags"] != .visible)
            var layout = model.view.columns(for: docs)
            layout[visibility: "created"] = .visible
            model.view.setColumns(layout, for: docs)
            check("a column can be shown", model.view.columns(for: docs)[visibility: "created"] == .visible)
            check("the layout is saved per folder", model.view.columns(for: drop)[visibility: "created"] != .visible)
            check("the layout is saved between launches", ViewSettings().columns(for: docs)[visibility: "created"] == .visible)
            check("listing reads tags", model.tab.items.first { $0.name == "Budget 2026.xlsx" }?.tags == ["Work"],
                  "\(model.tab.items.first { $0.name == "Budget 2026.xlsx" }?.tags ?? [])")
            model.view.reset()
            check("reset forgets the layouts", model.view.columns(for: docs)[visibility: "created"] != .visible)

            // S-033 See Properties
            model.tab.go(to: docs)
            try? await Task.sleep(for: .seconds(0.4))
            model.tab.selection = []
            model.showProperties()
            check("Properties with no selection shows the folder", model.propertiesURLs?.count == 1 && model.propertiesURLs?.first?.path == model.tab.currentFolder.path)
            model.closeProperties()
            model.tab.selection = Set(model.tab.items.filter { $0.name == "Notes.txt" }.map(\.url))
            model.showProperties()
            check("Properties shows the selected item", model.propertiesURLs?.first?.lastPathComponent == "Notes.txt")
            let props = model.propertiesURLs?.first.flatMap(ItemProperties.read)
            check("a file's properties are read", props?.name == "Notes.txt" && props?.size != nil && props?.location.hasSuffix("/Documents") == true, props?.location ?? "nil")
            model.closeProperties()
            check("Done closes the panel", model.propertiesURLs == nil)

            // S-034 Tag files
            model.tab.go(to: docs)
            try? await Task.sleep(for: .seconds(0.4))
            let notesURL = model.tab.items.first { $0.name == "Notes.txt" }!.url
            model.setTag("Blue", on: [notesURL], add: true)
            try? await Task.sleep(for: .seconds(0.8))
            check("a tag is added and shows in the listing", model.tab.items.first { $0.name == "Notes.txt" }?.tags == ["Blue"],
                  "\(model.tab.items.first { $0.name == "Notes.txt" }?.tags ?? [])")
            check("the Tags menu knows which tags every item has", model.commonTags(of: [notesURL]) == ["Blue"])
            model.setTag("Blue", on: [notesURL], add: false)
            try? await Task.sleep(for: .seconds(0.8))
            check("removing a tag takes it off", model.tab.items.first { $0.name == "Notes.txt" }?.tags.isEmpty == true)
            check("every standard tag except Gray has its own color", TagEditor.standard.filter { $0 != "Gray" }.allSatisfy { TagColor.color($0) != .gray })
            check("a custom tag is gray", TagColor.color("Taxes") == .gray)

            // S-032 Quick Look with Space
            model.tab.go(to: docs)
            try? await Task.sleep(for: .seconds(0.4))
            model.tab.selection = Set(model.tab.items.filter { $0.name == "Notes.txt" }.map(\.url))
            model.toggleQuickLook()
            try? await Task.sleep(for: .seconds(0.8))
            check("Space opens Quick Look", QuickLookController.shared.isVisible)
            check("Quick Look shows the selected file", QuickLookController.shared.urls.map(\.lastPathComponent) == ["Notes.txt"],
                  "\(QuickLookController.shared.urls.map(\.lastPathComponent))")
            model.tab.moveSelection(by: 1)
            QuickLookController.shared.update(model.tab.selectedItems.map(\.url))
            check("an arrow key moves to the next file", model.tab.selectedItems.first?.name == "Quarterly review.docx" && QuickLookController.shared.urls.first?.lastPathComponent == "Quarterly review.docx",
                  model.tab.selectedItems.first?.name ?? "nil")
            model.toggleQuickLook()
            try? await Task.sleep(for: .seconds(0.5))
            check("Space closes Quick Look", !QuickLookController.shared.isVisible)
            model.tab.selection = []
            model.tab.moveSelection(by: 1)
            check("an arrow key with nothing selected picks the first item", model.tab.selectedItems.first?.name == model.tab.items.first?.name)

            // S-031 Show a preview pane
            check("the preview pane starts hidden", model.view.showPreview == false)
            model.view.showPreview = true
            check("the preview pane setting is saved", ViewSettings().showPreview == true)
            model.view.showPreview = false
            check("Notes.txt previews as text and a photo as an image",
                  PreviewKind.kind(for: URL(fileURLWithPath: "/x/Notes.txt")) == .text && PreviewKind.kind(for: URL(fileURLWithPath: "/x/Beach.jpg")) == .image)
            model.view.reset()

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
