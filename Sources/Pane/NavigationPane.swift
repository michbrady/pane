import SwiftUI

/// The tree on the left: Quick access, then This Mac.
struct NavigationPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var places = model.places
        List(selection: $places.navSelection) {
            Section("Quick access") {
                ForEach(model.places.quickRoots) { NavRow(node: $0) }
                    // A folder dropped between rows is pinned there. Dropped on a row, it moves into that folder.
                    .dropDestination(for: URL.self) { urls, index in
                        for (offset, url) in urls.enumerated() { model.places.pin(url, at: index + offset) }
                    }
            }
            Section("This Mac") {
                ForEach(model.places.thisMacRoots) { NavRow(node: $0) }
            }
            if !model.places.cloudRoots.isEmpty {
                Section("Cloud") {
                    ForEach(model.places.cloudRoots) { NavRow(node: $0) }
                }
            }
            if !model.places.networkRoots.isEmpty {
                Section("Network") {
                    ForEach(model.places.networkRoots) { NavRow(node: $0) }
                }
            }
        }
        .onChange(of: model.places.navSelection) { _, id in
            guard let id, let url = Places.url(forNavID: id), url != model.tab.currentFolder else { return }
            model.tab.go(to: url)
        }
    }
}

private struct NavRow: View {
    @Environment(AppModel.self) private var model
    let node: NavNode

    var body: some View {
        if let kids = node.children {
            DisclosureGroup(isExpanded: expansion) {
                ForEach(kids) { NavRow(node: $0) }
            } label: {
                label
            }
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: Space.xs) {
            rowLabel
            if node.ejectable {
                Spacer(minLength: 0)
                Button("Eject", systemImage: "eject.fill") { model.places.eject(node) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Eject \(node.name)")
            }
        }
        .tag(node.id)
    }

    private var rowLabel: some View {
        Label {
            Text(node.name)
        } icon: {
            Image(nsImage: IconCache.icon(for: node.url, isFolder: true))
                .resizable()
                .frame(width: Layout.rowIcon, height: Layout.rowIcon)
        }
        .acceptsFileDrops(into: node.url, model: model)
        .onMiddleClick { model.newTab(at: node.url) }
        .contextMenu {
            Button("Open in New Tab") { model.newTab(at: node.url) }
            Button("Open in Terminal") { model.openInTerminal(node.url) }
            if model.places.isPinned(node.url) {
                Button("Unpin from Quick access") { model.places.unpin(node.url) }
            } else {
                Button("Pin to Quick access") { model.places.pin(node.url) }
            }
        }
        .help("Show folders inside \(node.name)")
    }

    private var expansion: Binding<Bool> {
        Binding(
            get: { model.places.expanded.contains(node.id) },
            set: { isOn in
                if isOn { model.places.expanded.insert(node.id) } else { model.places.expanded.remove(node.id) }
            })
    }
}
