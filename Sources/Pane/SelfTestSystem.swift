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
    }
}
