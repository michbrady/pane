import SwiftUI

/// The tree on the left: Quick access, then This Mac.
struct NavigationPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.navSelection) {
            Section("Quick access") {
                ForEach(model.quickRoots) { NavRow(node: $0) }
            }
            Section("This Mac") {
                ForEach(model.thisMacRoots) { NavRow(node: $0) }
            }
        }
        .onChange(of: model.navSelection) { _, id in
            guard let id, let url = AppModel.url(forNavID: id), url != model.currentFolder else { return }
            model.go(to: url)
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
        Label {
            Text(node.name)
        } icon: {
            Image(nsImage: IconCache.icon(for: node.url, isFolder: true))
                .resizable()
                .frame(width: Layout.rowIcon, height: Layout.rowIcon)
        }
        .tag(node.id)
        .acceptsFileDrops(into: node.url, model: model)
        .help("Show folders inside \(node.name)")
    }

    private var expansion: Binding<Bool> {
        Binding(
            get: { model.expanded.contains(node.id) },
            set: { isOn in
                if isOn { model.expanded.insert(node.id) } else { model.expanded.remove(node.id) }
            })
    }
}
