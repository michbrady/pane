import PaneKit
import SwiftUI

extension SortKey {
    var title: String {
        switch self {
        case .name: "Name"
        case .modified: "Date modified"
        case .created: "Date created"
        case .kind: "Type"
        case .size: "Size"
        }
    }
}

/// Explorer's Command bar as the window toolbar. Each button is a menu command too, and
/// dims when it does not apply. The toolbar is built outside the view tree, so it is handed the model.
struct CommandBar: ToolbarContent {
    let model: AppModel

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Button("New Folder", systemImage: "folder.badge.plus") { model.actions.newFolder() }
                .help("Make a new folder here (⇧⌘N)")
            Button("Cut", systemImage: "scissors") { model.actions.cutSelection() }
                .help("Cut the selected items (⌘X)")
                .disabled(!model.canCopy)
            Button("Copy", systemImage: "doc.on.doc") { model.actions.copySelection() }
                .help("Copy the selected items (⌘C)")
                .disabled(!model.canCopy)
            Button("Paste", systemImage: "doc.on.clipboard") { model.actions.paste() }
                .help("Paste the items here (⌘V)")
                .disabled(!model.actions.canPaste)
            Button("Rename", systemImage: "pencil") { model.actions.beginRename() }
                .help("Rename the selected item (F2)")
                .disabled(!model.actions.canRename)
            Button("Move to Trash", systemImage: "trash") { model.actions.trashSelection() }
                .help("Move the selected items to the Trash (⌫)")
                .disabled(model.tab.selection.isEmpty)
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Sort By", selection: Binding(
                    get: { model.view.sortKey },
                    set: { model.view.setSort($0, ascending: model.view.ascending) })) {
                    ForEach(SortKey.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Divider()
                Picker("Order", selection: Binding(
                    get: { model.view.ascending },
                    set: { model.view.setSort(model.view.sortKey, ascending: $0) })) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
                Toggle("Folders First", isOn: Binding(get: { model.view.foldersFirst }, set: { model.view.foldersFirst = $0 }))
            }
            .help("Choose how items are ordered")
            Menu("View", systemImage: model.view.mode.symbol) {
                Picker("View", selection: Binding(get: { model.view.mode }, set: { model.view.mode = $0 })) {
                    ForEach(ViewMode.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                Divider()
                Toggle("Show Hidden Items", isOn: Binding(get: { model.view.showHidden }, set: { model.view.showHidden = $0 }))
                Toggle("Show File Extensions", isOn: Binding(get: { model.view.showExtensions }, set: { model.view.showExtensions = $0 }))
            }
            .help("Choose how items are shown")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            Button("Preview Pane", systemImage: "sidebar.trailing") { model.view.showPreview.toggle() }
                .help("Show or hide the preview pane (⇧⌘P)")
        }
    }
}
