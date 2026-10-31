import PaneKit
import SwiftUI

/// The folder's items as rows: Name, Date modified, Type, Size.
struct DetailsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var tab = model.tab
        Table(of: FolderItem.self, selection: $tab.selection, sortOrder: sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: Space.sm) {
                    Image(nsImage: IconCache.icon(for: item.url, isFolder: item.isFolder))
                        .resizable()
                        .frame(width: Layout.rowIcon, height: Layout.rowIcon)
                    if model.actions.renamingURL == item.url {
                        RenameField(item: item)
                    } else {
                        Text(item.displayName(showExtensions: model.view.showExtensions))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(item.name)
                    }
                }
                .opacity(model.actions.isCut(item.url) ? Surfaces.cutOpacity : 1)
            }
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
                // A row is a file drag: to a folder in the Navigation pane, to Finder, or to another app.
                TableRow(item).draggable(item.url)
            }
        }
        // Dropping on empty space drops into the folder being shown.
        .acceptsFileDrops(into: model.tab.currentFolder, model: model)
        .contextMenu(forSelectionType: URL.self) { urls in
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
        } primaryAction: { urls in
            model.tab.open(Array(urls))
        }
        .onKeyPress(.return) {
            guard !model.tab.selection.isEmpty else { return .ignored }
            model.tab.openSelection()
            return .handled
        }
        .onKeyPress(.delete) {
            guard !model.tab.selection.isEmpty else { return .ignored }
            model.actions.trashSelection()
            return .handled
        }
        .onKeyPress(.deleteForward) {
            guard !model.tab.selection.isEmpty else { return .ignored }
            model.actions.trashSelection()
            return .handled
        }
        .onKeyPress(.escape) {
            model.actions.clearCut()
            return .handled
        }
        .alternatingRowBackgrounds(.disabled)
        .overlay { stateOverlay }
        .animation(nil, value: model.tab.items)
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

    @ViewBuilder
    private var stateOverlay: some View {
        if let error = model.tab.loadError {
            ContentUnavailableView {
                Label(error, systemImage: "lock.fill")
            } description: {
                Text("Pane needs Full Disk Access to read protected folders.")
            } actions: {
                Button("Open Settings") { Permissions.openFullDiskAccess() }
            }
        } else if model.tab.isSlow {
            ProgressView("Loading…")
        } else if model.tab.items.isEmpty, !model.tab.isLoading {
            ContentUnavailableView("This folder is empty", systemImage: "folder")
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
private struct RenameField: View {
    @Environment(AppModel.self) private var model
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
