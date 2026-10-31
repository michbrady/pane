import PaneKit
import SwiftUI

/// The folder's items as a table. Details shows Name, Date modified, Type, and Size. List shows names only.
struct DetailsView: View {
    @Environment(AppModel.self) private var model
    let listOnly: Bool

    var body: some View {
        @Bindable var tab = model.tab
        Group {
            if listOnly {
                Table(of: FolderItem.self, selection: $tab.selection, sortOrder: sortOrder) {
                    TableColumn("Name", value: \.name) { NameCell(model: model, item: $0) }
                } rows: {
                    ForEach(tab.items) { item in
                        // A row is a file drag: to a folder in the Navigation pane, to Finder, or to another app.
                        TableRow(item).draggable(item.url)
                    }
                }
            } else {
                Table(of: FolderItem.self, selection: $tab.selection, sortOrder: sortOrder) {
                    TableColumn("Name", value: \.name) { NameCell(model: model, item: $0) }
                        .width(min: 160, ideal: 280)
                    TableColumn("Date modified", value: \.sortModified) { item in
                        Text(item.modified.map(Format.date) ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 120, ideal: 150)
                    TableColumn("Type", value: \.kind) { item in
                        Text(item.kind).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .width(min: 80, ideal: 140)
                    TableColumn("Size", value: \.sortSize) { item in
                        Text(item.size.map(Format.size) ?? "—")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 60, ideal: 80)
                } rows: {
                    ForEach(tab.items) { item in
                        TableRow(item).draggable(item.url)
                    }
                }
            }
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            ItemMenu(model: model, urls: urls)
        } primaryAction: { urls in
            model.tab.open(Array(urls))
        }
        .alternatingRowBackgrounds(.disabled)
    }

    /// The Table shows the sort arrow from this, and a click on a header writes it back.
    private var sortOrder: Binding<[KeyPathComparator<FolderItem>]> {
        Binding(
            get: {
                let order: SortOrder = model.view.ascending ? .forward : .reverse
                switch model.view.sortKey {
                case .name: return [KeyPathComparator(\FolderItem.name, order: order)]
                case .modified: return [KeyPathComparator(\FolderItem.sortModified, order: order)]
                case .kind: return [KeyPathComparator(\FolderItem.kind, order: order)]
                case .size: return [KeyPathComparator(\FolderItem.sortSize, order: order)]
                }
            },
            set: { comparators in
                guard let first = comparators.first else { return }
                let path = first.keyPath as AnyKeyPath
                let key: SortKey = path == \FolderItem.sortModified ? .modified
                    : path == \FolderItem.kind ? .kind
                    : path == \FolderItem.sortSize ? .size : .name
                model.view.setSort(key, ascending: first.order == .forward)
            })
    }
}

/// The name column: the icon, and the name or the rename field.
/// Table cells do not reliably inherit the environment, so the model is passed in.
struct NameCell: View {
    let model: AppModel
    let item: FolderItem

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(nsImage: IconCache.icon(for: item.url, isFolder: item.isFolder))
                .resizable()
                .frame(width: Layout.rowIcon, height: Layout.rowIcon)
            if model.actions.renamingURL == item.url {
                RenameField(model: model, item: item)
            } else {
                Text(item.displayName(showExtensions: model.view.showExtensions))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.name)
            }
        }
        .opacity(model.actions.isCut(item.url) ? Surfaces.cutOpacity : 1)
    }
}

/// The context menu for items, in every view mode.
/// A menu is built outside the view's environment, so it is handed the model instead of reading it.
struct ItemMenu: View {
    let model: AppModel
    let urls: Set<URL>

    var body: some View {
        if !urls.isEmpty {
            Button("Open") { model.tab.open(Array(urls)) }
            if urls.count == 1 {
                Button("Rename") { model.actions.beginRename() }
                if let folder = model.tab.items.first(where: { urls.contains($0.url) && $0.isFolder }) {
                    Button("Open in New Tab") { model.newTab(at: folder.url) }
                    if model.isPinned(folder.url) {
                        Button("Unpin from Quick access") { model.unpin(folder.url) }
                    } else {
                        Button("Pin to Quick access") { model.pin(folder.url) }
                    }
                }
            }
        }
    }
}

enum Format {
    static func date(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .omitted) + " " + date.formatted(date: .omitted, time: .shortened)
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

enum Permissions {
    static func openFullDiskAccess() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}

/// The name field that replaces a row's name while renaming.
struct RenameField: View {
    let model: AppModel
    @FocusState private var focused: Bool
    let item: FolderItem

    var body: some View {
        @Bindable var actions = model.actions
        TextField("Name", text: $actions.renameText)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { model.actions.commitRename() }
            .onExitCommand { model.actions.cancelRename() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { model.actions.commitRename(fromBlur: true) }
            }
            .popover(isPresented: .constant(model.actions.renameError != nil), arrowEdge: .bottom) {
                Label(model.actions.renameError ?? "", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(Space.md)
            }
            .onAppear {
                focused = true
                // Select the name but not the extension, so typing keeps ".pdf".
                DispatchQueue.main.async {
                    let length = NameMaker.baseNameLength(item.name, isFolder: item.isFolder)
                    (NSApp.keyWindow?.firstResponder as? NSTextView)?.setSelectedRange(NSRange(location: 0, length: length))
                }
            }
    }
}
