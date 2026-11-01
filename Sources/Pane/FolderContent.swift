import PaneKit
import SwiftUI

/// The folder's items in the chosen view mode, with what every mode shares:
/// the keys, drops on empty space, and the empty and error states.
struct FolderContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.view.mode {
            case .details: DetailsView(listOnly: false)
            case .list: DetailsView(listOnly: true)
            case .icons: IconGridView()
            }
        }
        // Dropping on empty space drops into the folder being shown.
        .acceptsFileDrops(into: model.tab.currentFolder, model: model)
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
        .onKeyPress(.space) {
            guard !model.tab.selection.isEmpty || QuickLookController.shared.isShown else { return .ignored }
            model.toggleQuickLook()
            return .handled
        }
        .onKeyPress(.escape) {
            // Escape ends a search first. Otherwise it clears Cut.
            if model.tab.isSearching {
                model.tab.endSearch()
            } else {
                model.actions.clearCut()
            }
            return .handled
        }
        // After a lost connection the last list stays, dimmed, under the banner.
        .opacity(model.tab.isStale ? 0.45 : 1)
        .overlay(alignment: .top) { staleBanner }
        .overlay { stateOverlay }
        .animation(nil, value: model.tab.items)
    }

    /// "Connection lost." with Reconnect, over the dimmed last list.
    @ViewBuilder
    private var staleBanner: some View {
        if model.tab.loadProblem == .connectionLost {
            HStack(spacing: Space.md) {
                Label("Connection lost.", systemImage: "wifi.exclamationmark")
                Button("Reconnect") { model.tab.reconnect() }
            }
            .padding(Space.md)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .padding(Space.md)
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if model.tab.loadProblem == .unavailable {
            ContentUnavailableView {
                Label("This folder is no longer available", systemImage: "externaldrive.badge.xmark")
            } description: {
                Text("The drive or server it was on may have been disconnected.")
            } actions: {
                Button("Go to Home Folder") { model.tab.go(to: Locations.home) }
            }
        } else if model.tab.loadProblem == .connectionLost {
            // The banner says it, over the dimmed list. Nothing else covers the list.
            EmptyView()
        } else if let error = model.tab.loadError, model.tab.isRemote {
            ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
        } else if let error = model.tab.loadError {
            ContentUnavailableView {
                Label(error, systemImage: "lock.fill")
            } description: {
                Text("Pane needs Full Disk Access to read protected folders.")
            } actions: {
                Button("Open Settings") { Permissions.openFullDiskAccess() }
            }
        } else if model.tab.isSearching, model.tab.items.isEmpty {
            if model.tab.isSearchRunning {
                ProgressView("Searching…")
            } else {
                ContentUnavailableView.search(text: model.tab.searchText)
            }
        } else if model.tab.loadProblem == .notConnected {
            ContentUnavailableView {
                Label("Not connected to this server", systemImage: "network.slash")
            } description: {
                Text("Connect to it again to browse this folder.")
            } actions: {
                Button("Go to Home Folder") { model.tab.go(to: Locations.home) }
            }
        } else if model.tab.isSlow {
            VStack(spacing: Space.md) {
                ProgressView("Loading…")
                // A slow folder, like one on a far server, can be given up on.
                Button("Cancel") { model.tab.cancelLoad() }
            }
        } else if model.tab.items.isEmpty, !model.tab.isLoading {
            ContentUnavailableView("This folder is empty", systemImage: "folder")
        }
    }
}

/// Large icons in a grid, with names below.
struct IconGridView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool
    /// The item a Shift-click extends from.
    @State private var anchor: URL?

    var body: some View {
        let tab = model.tab
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Layout.iconCell), spacing: Space.sm, alignment: .top)], spacing: Space.sm) {
                ForEach(tab.items) { item in
                    IconCell(item: item, isSelected: tab.selection.contains(item.url))
                        .onTapGesture(count: 2) { tab.open([item.url]) }
                        .onTapGesture { select(item, in: tab) }
                        .draggable(item.url)
                        .contextMenu {
                            ItemMenu(model: model, urls: tab.selection.contains(item.url) ? tab.selection : [item.url])
                        }
                }
            }
            .padding(Space.md)
        }
        .contentShape(Rectangle())
        .onTapGesture { tab.selection = [] }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
    }

    /// Click selects one. Command-click adds or removes one. Shift-click selects from the last one clicked.
    private func select(_ item: FolderItem, in tab: FolderTab) {
        focused = true
        let keys = NSEvent.modifierFlags
        if keys.contains(.command) {
            if tab.selection.contains(item.url) { tab.selection.remove(item.url) } else { tab.selection.insert(item.url) }
            anchor = item.url
        } else if keys.contains(.shift), let anchor,
                  let from = tab.items.firstIndex(where: { $0.url == anchor }),
                  let to = tab.items.firstIndex(where: { $0.url == item.url }) {
            tab.selection = Set(tab.items[min(from, to)...max(from, to)].map(\.url))
        } else {
            tab.selection = [item.url]
            anchor = item.url
        }
    }
}

private struct IconCell: View {
    @Environment(AppModel.self) private var model
    let item: FolderItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: Space.xs) {
            Image(nsImage: IconCache.icon(for: item.url, isFolder: item.isFolder))
                .resizable()
                .frame(width: Layout.gridIcon, height: Layout.gridIcon)
            if model.actions.renamingURL == item.url {
                RenameField(model: model, item: item)
                    .multilineTextAlignment(.center)
            } else {
                Text(item.displayName(showExtensions: model.view.showExtensions))
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
                    .help(item.name)
            }
        }
        .padding(Space.xs)
        .frame(width: Layout.iconCell)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear,
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .opacity(model.actions.isCut(item.url) ? Surfaces.cutOpacity : 1)
        .contentShape(Rectangle())
    }
}
