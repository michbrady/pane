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
