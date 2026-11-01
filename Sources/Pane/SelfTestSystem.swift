import AppKit
import PaneKit

/// Self-test: Pane and the rest of the Mac (S-040 to S-048): the Command bar, the folder-open
/// handler, the shortcut, network and cloud folders.
extension SelfTest {
    static func system(_ c: Context) async {
        let model = c.model, docs = c.docs
        @MainActor func settle() async { await Wait.settle(c.model) }

        // S-041 Use the Command bar
        model.tab.go(to: docs)
        await settle()
        model.tab.selection = []
        check("Cut and Copy are dimmed with nothing selected", !model.canCopy)
        check("Rename is dimmed with nothing selected", !model.actions.canRename)
        model.tab.selection = Set(model.tab.items.prefix(1).map(\.url))
        check("Cut and Copy light up with a selection", model.canCopy)
        check("Rename lights up with one item selected", model.actions.canRename)
        model.actions.copySelection()
        check("Paste lights up when files are on the pasteboard", model.actions.canPaste)
        model.tab.selection = Set(model.tab.items.prefix(2).map(\.url))
        check("Rename dims with two items selected", !model.actions.canRename)
        check("every sort key has a name", SortKey.allCases.allSatisfy { !$0.title.isEmpty })
        model.tab.selection = []

        // S-045 Open in Terminal
        model.tab.go(to: docs)
        await settle()
        check("Terminal is installed, so Open in Terminal is available", model.canOpenInTerminal)
        let work = model.tab.items.first { $0.name == "Work" }
        model.tab.selection = Set([work?.url].compactMap { $0 })
        check("with a folder selected, Terminal opens that folder",
              OpenInTerminal.folder(selected: model.tab.selectedItems, current: model.tab.currentFolder).lastPathComponent == "Work")
        model.tab.selection = []
        check("with nothing selected, Terminal opens the folder shown",
              OpenInTerminal.folder(selected: model.tab.selectedItems, current: model.tab.currentFolder) == model.tab.currentFolder)

        // S-040 Guide Full Disk Access
        check("tests never show the Full Disk Access screen", !model.showFullDiskAccessGuide)
        _ = Permissions.hasFullDiskAccess
        check("Pane can tell whether it has Full Disk Access", true)
        model.showFullDiskAccessGuideForSnapshot()
        check("the screen shows when asked", model.showFullDiskAccessGuide)
        model.dismissFullDiskAccessGuide()
        check("Not Now closes it and it is not shown again", !model.showFullDiskAccessGuide && Prefs.defaults.bool(forKey: "pane.fdaGuideShown"))
    }
}
