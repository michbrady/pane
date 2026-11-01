import Foundation

/// The three places keyboard focus lives in a Pane window.
public enum FocusRegion: String, CaseIterable, Sendable {
    case list, navigation, address
}

/// F6 and Shift+F6: the order focus moves through the window, like Explorer.
public enum FocusCycle {
    /// The next region after `current`, or the previous one. The Navigation pane is skipped when it is hidden.
    public static func next(after current: FocusRegion, reverse: Bool = false, navigationShown: Bool = true) -> FocusRegion {
        let order: [FocusRegion] = navigationShown ? [.list, .navigation, .address] : [.list, .address]
        guard let index = order.firstIndex(of: current) else { return .list }
        let step = reverse ? order.count - 1 : 1
        return order[(index + step) % order.count]
    }
}

/// What VoiceOver reads for a row: the name, the kind, and the size.
public enum ItemSpeech {
    public static func label(for item: FolderItem, showExtensions: Bool = true) -> String {
        var parts = [item.displayName(showExtensions: showExtensions), item.kind.isEmpty ? (item.isFolder ? "Folder" : "File") : item.kind]
        if !item.isFolder, let size = item.size {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if item.isOnlineOnly { parts.append("Online only") }
        return parts.joined(separator: ", ")
    }
}
