import AppKit
import PaneKit

/// Self-test: views and tabs (S-020 to S-027): sort, hidden files, pins, tabs, view modes, columns.
extension SelfTest {
    static func views(_ c: Context) async {
        let model = c.model, home = c.home, docs = c.docs, work = c.work, drop = c.drop
        let fm = FileManager.default
        @MainActor func settle() async { await Wait.settle(c.model) }
        // S-020 Sort by column and S-021 Folders first
        model.tab.go(to: docs)
        await settle()
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
        await settle()
        check("hidden items are off by default", !model.tab.items.contains { $0.name == ".secret" })
        model.view.showHidden = true
        await settle()
        check("Show Hidden Items lists dotfiles", model.tab.items.contains { $0.name == ".secret" })
        model.view.showHidden = false
        await settle()
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
        await settle()
        check("a pinned folder that was renamed still shows, under its new name", model.quickRoots.last?.name == "Work 2", "\(model.quickRoots.map(\.name))")
        model.unpin(moved)
        check("Unpin removes the row", !model.quickRoots.contains { $0.name == "Work 2" })
        check("pins are saved", Prefs.defaults.array(forKey: "pane.pins") != nil)

        // S-026 Tabs and S-027 Open a folder in a new tab
        model.tab.go(to: docs)
        await settle()
        let first = model.tab
        check("Pane starts with one tab", model.tabs.count == 1)
        first.selection = Set(first.items.prefix(1).map(\.url))
        model.newTab(at: drop)
        await settle()
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
        await settle()

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
        await settle()
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
    }
}
