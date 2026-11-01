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
                Table(of: FolderItem.self, selection: $tab.selection, sortOrder: sortOrder, columnCustomization: columnLayout) {
                    TableColumn("Name", value: \.name) { NameCell(model: model, item: $0) }
                        .width(min: 160, ideal: 280)
                        .customizationID("name")
                    TableColumn("Date modified", value: \.sortModified) { item in
                        Text(item.modified.map(Format.date) ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 130, ideal: 175)
                    .customizationID("modified")
                    TableColumn("Date created", value: \.sortCreated) { item in
                        Text(item.created.map(Format.date) ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 130, ideal: 175)
                    .customizationID("created")
                    .defaultVisibility(.hidden)
                    TableColumn("Type", value: \.kind) { item in
                        Text(item.kind).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .width(min: 80, ideal: 140)
                    .customizationID("kind")
                    TableColumn("Tags") { item in
                        TagDots(tags: item.tags).foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 100)
                    .customizationID("tags")
                    .defaultVisibility(.hidden)
                    TableColumn("Size", value: \.sortSize) { item in
                        Text(item.size.map(Format.size) ?? "—")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 60, ideal: 80)
                    .customizationID("size")
                    // Search results come from many folders, so they show where each one lives.
                    TableColumn("Location") { item in
                        Text(Self.locationText(item))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(item.url.deletingLastPathComponent().path)
                    }
                    .width(min: 100, ideal: 220)
                    .customizationID("location")
                    .defaultVisibility(tab.isSearching ? .visible : .hidden)
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

    /// The folder an item is in, with the home folder written as "~".
    private static func locationText(_ item: FolderItem) -> String {
        let folder = item.url.deletingLastPathComponent().standardizedFileURL.path
        let home = Locations.home.path
        return folder == home ? "~" : (folder.hasPrefix(home + "/") ? "~" + folder.dropFirst(home.count) : folder)
    }

    /// Which columns show, and their order and widths. Saved for each folder.
    private var columnLayout: Binding<TableColumnCustomization<FolderItem>> {
        Binding(
            get: { model.view.columns(for: model.tab.currentFolder) },
            set: { model.view.setColumns($0, for: model.tab.currentFolder) })
    }

    /// The Table shows the sort arrow from this, and a click on a header writes it back.
    private var sortOrder: Binding<[KeyPathComparator<FolderItem>]> {
        Binding(
            get: {
                let order: SortOrder = model.view.ascending ? .forward : .reverse
                switch model.view.sortKey {
                case .name: return [KeyPathComparator(\FolderItem.name, order: order)]
                case .modified: return [KeyPathComparator(\FolderItem.sortModified, order: order)]
                case .created: return [KeyPathComparator(\FolderItem.sortCreated, order: order)]
                case .kind: return [KeyPathComparator(\FolderItem.kind, order: order)]
                case .size: return [KeyPathComparator(\FolderItem.sortSize, order: order)]
                }
            },
            set: { comparators in
                guard let first = comparators.first else { return }
                let path = first.keyPath as AnyKeyPath
                let key: SortKey = path == \FolderItem.sortModified ? .modified
                    : path == \FolderItem.sortCreated ? .created
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
                if item.isOnlineOnly {
                    Image(systemName: "icloud")
                        .foregroundStyle(.secondary)
                        .help("Not on this Mac yet. Opening it downloads it.")
                        .accessibilityLabel("Online only")
                }
            }
        }
        .opacity(model.actions.isCut(item.url) ? Surfaces.cutOpacity : 1)
        // VoiceOver reads the row as one thing: name, kind, and size.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ItemSpeech.label(for: item, showExtensions: model.view.showExtensions))
    }
}

/// The context menu for items, in every view mode: an icon row (Cut, Copy, Rename, Delete), then the list.
/// The entries come from `ContextMenuPlan`. A menu is built outside the view's environment, so it is handed the model.
struct ItemMenu: View {
    let model: AppModel
    let urls: Set<URL>

    var body: some View {
        if !urls.isEmpty {
            let chosen = model.tab.items.filter { urls.contains($0.url) }
            let plan = ContextMenuPlan(selectionCount: urls.count, hasFolder: chosen.contains(where: \.isFolder),
                                       isOnlyFolder: chosen.count == 1 && chosen[0].isFolder, onServer: model.tab.isRemote,
                                       isPinned: chosen.first.map { model.places.isPinned($0.url) } ?? false)
            ControlGroup {
                ForEach(plan.iconRow, id: \.self) { entry in
                    Button(Self.title(entry), systemImage: Self.symbol(entry)) { Self.run(entry, urls: urls, model: model) }
                        .labelStyle(.iconOnly)
                        .help(Self.title(entry))
                }
            }
            ForEach(plan.items, id: \.self) { entry in
                switch entry {
                case .tags: TagMenu(model: model, urls: Array(urls))
                case .openWith: OpenWithMenu(urls: Array(urls))
                default: Button(Self.title(entry)) { Self.run(entry, urls: urls, model: model) }
                }
            }
        }
    }

    /// Menu actions work on what was right-clicked, which may not be what was selected.
    static func run(_ entry: ContextMenuPlan.Entry, urls: Set<URL>, model: AppModel) {
        if model.tab.selection != urls { model.tab.selection = urls }
        let folder = model.tab.items.first { urls.contains($0.url) && $0.isFolder }
        switch entry {
        case .cut: model.actions.cutSelection()
        case .copy: model.actions.copySelection()
        case .rename: model.actions.beginRename()
        case .delete: model.actions.trashSelection()
        case .open: model.tab.open(Array(urls))
        case .properties: model.showProperties()
        case .openInNewTab: if let folder { model.newTab(at: folder.url) }
        case .openInTerminal: if let folder { model.openInTerminal(folder.url) }
        case .pin: if let folder { model.places.pin(folder.url) }
        case .unpin: if let folder { model.places.unpin(folder.url) }
        case .openWith, .tags: break
        }
    }

    static func title(_ entry: ContextMenuPlan.Entry) -> String {
        switch entry {
        case .cut: "Cut"
        case .copy: "Copy"
        case .rename: "Rename"
        case .delete: "Delete"
        case .open: "Open"
        case .openWith: "Open With"
        case .properties: "Properties"
        case .tags: "Tags"
        case .openInNewTab: "Open in New Tab"
        case .openInTerminal: "Open in Terminal"
        case .pin: "Pin to Quick access"
        case .unpin: "Unpin from Quick access"
        }
    }

    static func symbol(_ entry: ContextMenuPlan.Entry) -> String {
        switch entry {
        case .cut: "scissors"
        case .copy: "doc.on.doc"
        case .rename: "pencil"
        case .delete: "trash"
        default: "circle"
        }
    }
}

/// Open With: the apps that can open the file, by name. The first one is the default.
struct OpenWithMenu: View {
    let urls: [URL]

    var body: some View {
        let apps = urls.first.map { NSWorkspace.shared.urlsForApplications(toOpen: $0) } ?? []
        Menu("Open With") {
            ForEach(apps.prefix(12), id: \.self) { app in
                Button(FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")) {
                    NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            if apps.isEmpty { Text("No apps found") }
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
    /// True when Pane has Full Disk Access. macOS lets only such an app open its own privacy
    /// database, so being able to open it is the test.
    static var hasFullDiskAccess: Bool {
        let path = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

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
