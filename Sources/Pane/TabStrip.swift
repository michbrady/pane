import PaneKit
import SwiftUI

/// The row of tabs above the Address bar, with a plus button. Each tab shows its folder's name.
struct TabStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                TabButton(tab: tab, index: index, isActive: index == model.activeIndex)
            }
            Button("New Tab", systemImage: "plus") { model.newTab() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Open the current folder in a new tab (⌘T)")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.md)
        .frame(height: Layout.tabStripHeight)
        .background(.bar)
    }
}

private struct TabButton: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false
    let tab: FolderTab
    let index: Int
    let isActive: Bool

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(nsImage: IconCache.icon(for: tab.currentFolder, isFolder: true))
                .resizable()
                .frame(width: Layout.rowIcon, height: Layout.rowIcon)
            Text(tab.currentName)
                .lineLimit(1)
                .truncationMode(.middle)
            // The close icon shows on hover, and always on the active tab when there is more than one.
            Button("Close Tab", systemImage: "xmark") { model.close(tab) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.caption)
                .opacity(hovering || (isActive && model.tabs.count > 1) ? 1 : 0)
                .disabled(model.tabs.count < 2)
                .help("Close this tab (⌘W)")
        }
        .padding(.horizontal, Space.sm)
        .frame(height: Layout.tabHeight)
        .frame(minWidth: 96, maxWidth: 220)
        .background(isActive ? Surfaces.field : Color.clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Surfaces.hairline)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.select(index) }
        .onHover { hovering = $0 }
        .acceptsFileDrops(into: tab.currentFolder, model: model)
        .contextMenu {
            Button("New Tab") { model.newTab(at: tab.currentFolder) }
            Button("Close Tab") { model.close(tab) }
                .disabled(model.tabs.count < 2)
            Button("Close Other Tabs") { model.closeOtherTabs(except: tab) }
                .disabled(model.tabs.count < 2)
        }
        .accessibilityLabel("\(tab.currentName), tab \(index + 1) of \(model.tabs.count)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
