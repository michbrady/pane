import PaneKit
import SwiftUI

/// The strip at the bottom: how many items, and what is selected.
struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Text(model.actions.statusMessage ?? summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            // The same choice as View > As Details and As Icons.
            ForEach([ViewMode.details, ViewMode.icons], id: \.self) { mode in
                Button(mode.title, systemImage: mode.symbol) { model.view.mode = mode }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(model.view.mode == mode ? Color.accentColor : .secondary)
                    .help("Show items as \(mode.title.lowercased()) (⌃⌘\(mode == .details ? "1" : "3"))")
            }
        }
        .padding(.horizontal, Space.md)
        .frame(height: Layout.statusBarHeight)
        .background(.bar)
    }

    private var summary: String {
        SelectionSummary.text(itemCount: model.tab.items.count, selected: model.tab.selectedItems,
                              onlineOnly: model.tab.items.filter(\.isOnlineOnly).count)
    }
}
