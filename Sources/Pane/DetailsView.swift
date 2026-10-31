import PaneKit
import SwiftUI

/// The folder's items as rows: Name, Date modified, Type, Size.
struct DetailsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Table(model.items, selection: $model.selection) {
            TableColumn("Name") { item in
                HStack(spacing: Space.sm) {
                    Image(nsImage: IconCache.icon(for: item.url, isFolder: item.isFolder))
                        .resizable()
                        .frame(width: Layout.rowIcon, height: Layout.rowIcon)
                    if model.renamingURL == item.url {
                        RenameField(item: item)
                    } else {
                        Text(item.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(item.name)
                    }
                }
                .opacity(model.isCut(item.url) ? Surfaces.cutOpacity : 1)
            }
            .width(min: 160, ideal: 280)
            TableColumn("Date modified") { item in
                Text(item.modified.map(Format.date) ?? "")
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)
            TableColumn("Type") { item in
                Text(item.kind).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 80, ideal: 140)
            TableColumn("Size") { item in
                Text(item.size.map(Format.size) ?? "—")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            if !urls.isEmpty {
                Button("Open") { model.open(Array(urls)) }
                if urls.count == 1 {
                    Button("Rename") { model.beginRename() }
                }
            }
        } primaryAction: { urls in
            model.open(Array(urls))
        }
        .onKeyPress(.return) {
            guard !model.selection.isEmpty else { return .ignored }
            model.openSelection()
            return .handled
        }
        .onKeyPress(.delete) {
            guard !model.selection.isEmpty else { return .ignored }
            model.trashSelection()
            return .handled
        }
        .onKeyPress(.deleteForward) {
            guard !model.selection.isEmpty else { return .ignored }
            model.trashSelection()
            return .handled
        }
        .onKeyPress(.escape) {
            model.clearCut()
            return .handled
        }
        .alternatingRowBackgrounds(.disabled)
        .overlay { stateOverlay }
        .animation(nil, value: model.items)
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if let error = model.loadError {
            ContentUnavailableView {
                Label(error, systemImage: "lock.fill")
            } description: {
                Text("Pane needs Full Disk Access to read protected folders.")
            } actions: {
                Button("Open Settings") { Permissions.openFullDiskAccess() }
            }
        } else if model.isSlow {
            ProgressView("Loading…")
        } else if model.items.isEmpty, !model.isLoading {
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
        @Bindable var model = model
        TextField("Name", text: $model.renameText)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { model.commitRename() }
            .onExitCommand { model.cancelRename() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { model.commitRename(fromBlur: true) }
            }
            .popover(isPresented: .constant(model.renameError != nil), arrowEdge: .bottom) {
                Label(model.renameError ?? "", systemImage: "exclamationmark.triangle.fill")
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
