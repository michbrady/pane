import AppKit
import PaneKit

/// Self-test: find and inspect (S-030 to S-035): Properties, tags, Quick Look, preview, search.
extension SelfTest {
    static func find(_ c: Context) async {
        let model = c.model, home = c.home, docs = c.docs
        @MainActor func settle() async { await Wait.settle(c.model) }
        // S-033 See Properties
        model.tab.go(to: docs)
        await settle()
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
        await settle()
        let notesURL = model.tab.items.first { $0.name == "Notes.txt" }!.url
        model.setTag("Blue", on: [notesURL], add: true)
        await settle()
        check("a tag is added and shows in the listing", model.tab.items.first { $0.name == "Notes.txt" }?.tags == ["Blue"],
              "\(model.tab.items.first { $0.name == "Notes.txt" }?.tags ?? [])")
        check("the Tags menu knows which tags every item has", model.commonTags(of: [notesURL]) == ["Blue"])
        model.setTag("Blue", on: [notesURL], add: false)
        await settle()
        check("removing a tag takes it off", model.tab.items.first { $0.name == "Notes.txt" }?.tags.isEmpty == true)
        check("every standard tag except Gray has its own color", TagEditor.standard.filter { $0 != "Gray" }.allSatisfy { TagColor.color($0) != .gray })
        check("a custom tag is gray", TagColor.color("Taxes") == .gray)

        // S-032 Quick Look with Space
        model.tab.go(to: docs)
        await settle()
        model.tab.selection = Set(model.tab.items.filter { $0.name == "Notes.txt" }.map(\.url))
        model.toggleQuickLook()
        await Wait.until { QuickLookController.shared.isShown }
        check("Space opens Quick Look (Pane opened the panel)", QuickLookController.shared.isShown)
        check("Quick Look shows the selected file", QuickLookController.shared.urls.map(\.lastPathComponent) == ["Notes.txt"],
              "\(QuickLookController.shared.urls.map(\.lastPathComponent))")
        model.tab.moveSelection(by: 1)
        QuickLookController.shared.update(model.tab.selectedItems.map(\.url))
        check("an arrow key moves to the next file", model.tab.selectedItems.first?.name == "Quarterly review.docx" && QuickLookController.shared.urls.first?.lastPathComponent == "Quarterly review.docx",
              model.tab.selectedItems.first?.name ?? "nil")
        model.toggleQuickLook()
        // The panel closes with a short animation, so wait for it rather than guess.
        await Wait.until { !QuickLookController.shared.isShown }
        check("Space closes Quick Look", !QuickLookController.shared.isShown)
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

        // S-030 Search from the top bar
        model.tab.go(to: home)
        await settle()
        model.tab.searchText = "roadmap"
        model.tab.search("roadmap")
        await Wait.until { !model.tab.isSearchRunning }
        check("search finds a file in a folder below, ignoring case", model.tab.isSearching && model.tab.items.map(\.name) == ["Roadmap.key"],
              "\(model.tab.items.map(\.name))")
        check("the search has finished", !model.tab.isSearchRunning)
        model.tab.search("zzzz")
        await Wait.until { !model.tab.isSearchRunning }
        check("no results leaves an empty list and says so", model.tab.items.isEmpty && model.tab.isSearching && !model.tab.isSearchRunning)
        model.tab.endSearch()
        await settle()
        check("Escape restores the folder", !model.tab.isSearching && model.tab.searchText.isEmpty && model.tab.items.contains { $0.name == "Documents" })
        model.tab.searchText = "notes"
        model.tab.search("notes")
        await Wait.until { !model.tab.isSearchRunning }
        check("a search can find several files", model.tab.items.contains { $0.name == "Notes.txt" })
        model.tab.go(to: docs)
        check("going to another folder ends the search", !model.tab.isSearching && model.tab.searchText.isEmpty)
        await settle()
        check("and shows that folder", model.tab.items.contains { $0.name == "Work" })
        model.tab.search("   ")
        check("a search of only spaces does nothing", !model.tab.isSearching)
        model.focusSearch()
        check("Find asks for the Search box", model.searchFocusRequests > 0)
    }
}
