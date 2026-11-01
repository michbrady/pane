import Foundation

/// The words in the Status bar: how many items, and what is selected.
public enum SelectionSummary {
    /// "12 items", or "3 items selected 4.1 MB". Folders have no size, so only files add up.
    public static func text(itemCount: Int, selected: [FolderItem], onlineOnly: Int = 0) -> String {
        let online = onlineOnly > 0 ? "  ·  \(onlineOnly) online only" : ""
        guard !selected.isEmpty else { return (itemCount == 1 ? "1 item" : "\(itemCount) items") + online }
        let words = selected.count == 1 ? "1 item selected" : "\(selected.count) items selected"
        let bytes = selected.compactMap(\.size).reduce(0, +)
        guard bytes > 0 else { return words + online }
        return "\(words)  \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))" + online
    }
}
