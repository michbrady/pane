import Foundation

/// Which folder "Open in Terminal" opens.
public enum OpenInTerminal {
    /// One folder selected: that folder. One file: the folder it is in. Anything else: the folder shown.
    public static func folder(selected: [FolderItem], current: URL) -> URL {
        guard selected.count == 1, let item = selected.first else { return current }
        return item.isFolder ? item.url : item.url.deletingLastPathComponent()
    }
}
