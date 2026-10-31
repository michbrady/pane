import SwiftUI

/// The strip at the bottom: how many items, and what is selected.
struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Text(summary)
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
        let total = model.tab.items.count
        let picked = model.tab.selectedItems
        guard !picked.isEmpty else { return total == 1 ? "1 item" : "\(total) items" }
        let word = picked.count == 1 ? "1 item selected" : "\(picked.count) items selected"
        let bytes = picked.compactMap(\.size).reduce(0, +)
        return bytes > 0 ? "\(word)  \(Format.size(bytes))" : word
    }
}
