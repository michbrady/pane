import Foundation

/// What a drag does when it lands: move or copy.
public enum DropRules {
    /// Option copies and Command moves. With neither key, a drag inside one volume
    /// moves and a drag to another volume copies, as in Explorer.
    public static func mode(sameVolume: Bool, option: Bool, command: Bool) -> PasteMode {
        if option { return .copy }
        if command { return .move }
        return sameVolume ? .move : .copy
    }

    /// True when every source sits on the same volume as the destination folder.
    public static func sameVolume(_ sources: [URL], as destination: URL) -> Bool {
        guard let target = volumeID(destination) else { return false }
        return sources.allSatisfy { volumeID($0)?.isEqual(target) == true }
    }

    private static func volumeID(_ url: URL) -> NSObjectProtocol? {
        try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
    }
}
