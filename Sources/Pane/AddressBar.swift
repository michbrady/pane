import PaneKit
import SwiftUI

/// The row under the toolbar: Go back, Go forward, Go up, then the folder's
/// breadcrumbs. Custom chrome: breadcrumbs, a typed path, and sibling menus
/// need the full width, and the system toolbar cannot hold them.
struct AddressBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.sm) {
            Button("Go back", systemImage: "chevron.backward") { model.goBack() }
                .disabled(!model.canGoBack)
                .help("Go back to the previous folder (⌘[)")
            Button("Go forward", systemImage: "chevron.forward") { model.goForward() }
                .disabled(!model.canGoForward)
                .help("Go forward to the next folder (⌘])")
            Button("Go up", systemImage: "chevron.up") { model.goUp() }
                .disabled(!model.canGoUp)
                .help("Go up to the parent folder (⌘↑)")
            field
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, Space.md)
        .frame(height: Layout.addressBarHeight)
        .background(.bar)
    }

    private var field: some View {
        ZStack {
            if model.isEditingAddress {
                AddressField()
            } else {
                BreadcrumbTrail()
            }
        }
        .padding(.horizontal, Space.sm)
        .frame(height: Space.xl + Space.sm)
        .background(Surfaces.field, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(model.addressError == nil ? Surfaces.hairline : Color.red)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !model.isEditingAddress { model.beginEditingAddress() } }
        .help("Type a path (⌘L)")
    }
}

private struct BreadcrumbTrail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let chain = Breadcrumbs.chain(for: model.currentFolder)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(chain, id: \.self) { url in
                    Button(Locations.displayName(for: url)) { model.go(to: url) }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Space.xs)
                        .help("Go to \(Locations.displayName(for: url))")
                    SiblingsMenu(folder: url)
                }
            }
        }
        // Short paths start at the left. A long one scrolls to show the current folder.
        .defaultScrollAnchor(.leading, for: .alignment)
        .defaultScrollAnchor(.trailing, for: .initialOffset)
        .defaultScrollAnchor(.trailing, for: .sizeChanges)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The chevron after a breadcrumb: lists the folders inside it.
private struct SiblingsMenu: View {
    @Environment(AppModel.self) private var model
    let folder: URL
    private static let limit = 30

    var body: some View {
        let name = Locations.displayName(for: folder)
        let folders = ((try? FolderLister.list(folder)) ?? []).filter(\.isFolder)
        Menu {
            if folders.isEmpty {
                Text("No Folders")
            }
            ForEach(folders.prefix(Self.limit)) { item in
                Button(item.name) { model.go(to: item.url) }
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Show folders inside \(name)")
    }
}

private struct AddressField: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: Space.sm) {
            TextField("Address", text: $model.addressText)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { model.commitAddress() }
                .onExitCommand { model.cancelEditingAddress() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { model.cancelEditingAddress() }
                }
            if let error = model.addressError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .onAppear {
            focused = true
            DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil) }
        }
    }
}
