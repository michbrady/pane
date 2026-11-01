import PaneKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        NavigationSplitView {
            NavigationPane()
                .navigationSplitViewColumnWidth(
                    min: Layout.navigationMin, ideal: Layout.navigationIdeal, max: Layout.navigationMax)
        } detail: {
            FolderPage()
        }
        .inspector(isPresented: Binding(get: { model.view.showPreview }, set: { model.view.showPreview = $0 })) {
            PreviewPane(model: model)
                .inspectorColumnWidth(min: Layout.previewMin, ideal: Layout.previewIdeal, max: Layout.previewMax)
        }
        .navigationTitle(model.tab.currentName)
        .noInitialFocus()
        .onChange(of: undoManager, initial: true) { _, manager in model.actions.windowUndoManager = manager }
        .onChange(of: model.tab.selection) { QuickLookController.shared.update(model.tab.selectedItems.map(\.url)) }
        .sheet(isPresented: .init(get: { model.actions.progressVisible && model.actions.pendingConflict == nil }, set: { _ in })) {
            OperationSheet()
        }
        .sheet(isPresented: .init(get: { model.showFullDiskAccessGuide }, set: { if !$0 { model.dismissFullDiskAccessGuide() } })) {
            FullDiskAccessSheet(model: model)
        }
        .sheet(isPresented: .init(get: { model.connections.showConnectSheet }, set: { if !$0 { model.connections.closeConnectSheet() } })) {
            ConnectSheet(model: model)
        }
        .sheet(isPresented: .init(get: { model.propertiesURLs != nil }, set: { if !$0 { model.closeProperties() } })) {
            if let urls = model.propertiesURLs { PropertiesSheet(model: model, urls: urls) }
        }
        .sheet(isPresented: .init(get: { model.actions.pendingConflict != nil }, set: { _ in })) {
            ConflictSheet()
        }
        .confirmationDialog(deleteTitle, isPresented: .init(get: { model.actions.pendingDelete != nil }, set: { if !$0 { model.actions.pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Immediately", role: .destructive) { model.actions.deleteImmediately() }
            Button("Cancel", role: .cancel) { model.actions.pendingDelete = nil }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Pane", isPresented: .init(get: { model.actions.alertMessage != nil }, set: { if !$0 { model.actions.alertMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.actions.alertMessage ?? "")
        }
        .background(FrameAutosave(name: "PaneMain"))
        .task {
            AppDelegate.shared?.onOpen = { urls in model.openFromOutside(urls) }
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }
}

extension ContentView {
    fileprivate var deleteTitle: String {
        guard let urls = model.actions.pendingDelete else { return "" }
        return urls.count == 1
            ? "Delete \u{201C}\(urls[0].lastPathComponent)\u{201D} Immediately?"
            : "Delete \(urls.count) Items Immediately?"
    }
}

/// The content column: Address bar, Details view, Status bar, and the Command bar.
struct FolderPage: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var tab = model.tab
        VStack(spacing: 0) {
            TabStrip()
            Divider()
            AddressBar()
            Divider()
            FolderContent()
            Divider()
            StatusBar()
        }
        // The Command bar buttons come in S-041, so they stay dimmed until then.
        .background {
            // F4 focuses the Address bar and F3 the Search box, like Explorer.
            // Cmd-L and Cmd-F are in the menus.
            Button("Go to Address") { model.beginEditingAddress() }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF4FunctionKey)!)), modifiers: [])
                .opacity(0)
                .accessibilityHidden(true)
            Button("Search") { model.focusSearch() }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF3FunctionKey)!)), modifiers: [])
                .opacity(0)
                .accessibilityHidden(true)
        }
        .searchable(text: $tab.searchText, prompt: "Search")
        .searchFocused($searchFocused)
        .onChange(of: tab.searchText) { _, text in tab.search(text) }
        .onChange(of: model.searchFocusRequests) { searchFocused = true }
        .toolbar { CommandBar(model: model) }
    }
}

/// Shows a long copy or move: what is happening, how far along, and Cancel.
struct OperationSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(title).font(.headline)
            if let p = model.actions.progress {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                Text(p.current).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.actions.cancelOperation() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Space.xl)
        .frame(width: Layout.sheetWidth)
        .noInitialFocus()
    }

    private var title: String {
        guard let p = model.actions.progress else { return model.actions.progressTitle + "…" }
        return "\(model.actions.progressTitle) \(min(p.done + 1, p.total)) of \(p.total)"
    }
}

/// Asks what to do when a pasted item's name is taken: Replace, Skip, or Keep Both.
struct ConflictSheet: View {
    @Environment(AppModel.self) private var model
    @State private var applyToAll = false

    var body: some View {
        if let pending = model.actions.pendingConflict {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("\u{201C}\(pending.conflict.existing.lastPathComponent)\u{201D} already exists")
                        .font(.headline)
                    Text("Choose what to do with the item you are pasting.")
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: Space.sm) {
                    ConflictRow(title: "Already here", item: pending.existing)
                    ConflictRow(title: "Pasting", item: pending.incoming)
                }
                Toggle("Do this for all conflicts", isOn: $applyToAll)
                HStack {
                    Button("Cancel") { model.actions.resolveConflict(.cancel, applyToAll: false) }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Keep Both") { model.actions.resolveConflict(.keepBoth, applyToAll: applyToAll) }
                    Button("Replace") { model.actions.resolveConflict(.replace, applyToAll: applyToAll) }
                    // Skip is the default, so a stray Return never overwrites anything.
                    Button("Skip") { model.actions.resolveConflict(.skip, applyToAll: applyToAll) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Space.xl)
            .frame(width: Layout.sheetWidth)
            .noInitialFocus()
        }
    }
}

private struct ConflictRow: View {
    let title: String
    let item: FolderItem?

    var body: some View {
        HStack(spacing: Space.md) {
            if let item {
                Image(nsImage: IconCache.icon(for: item.url, isFolder: item.isFolder))
                    .resizable()
                    .frame(width: Space.xxl + Space.sm, height: Space.xxl + Space.sm)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.callout.bold())
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Space.md)
        .background(Surfaces.field, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var detail: String {
        guard let item else { return "" }
        let size = item.size.map(Format.size) ?? "Folder"
        let date = item.modified.map(Format.date) ?? ""
        return [size, date].filter { !$0.isEmpty }.joined(separator: "  ")
    }
}
