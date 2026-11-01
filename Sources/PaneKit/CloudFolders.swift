import Foundation

/// A cloud service's folder on this Mac, like iCloud Drive or Dropbox.
public struct CloudFolder: Equatable, Sendable {
    public let url: URL
    public let name: String

    public init(url: URL, name: String) {
        self.url = url
        self.name = name
    }
}

public enum CloudLocations {
    /// iCloud Drive, then every provider macOS keeps under `~/Library/CloudStorage`
    /// (Dropbox, Google Drive, OneDrive, Box, and others), by the name a person knows.
    public static func list(home: URL) -> [CloudFolder] {
        var found: [CloudFolder] = []
        let icloud = home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        if isFolder(icloud) { found.append(CloudFolder(url: icloud.standardizedFileURL, name: "iCloud Drive")) }
        let storage = home.appending(path: "Library/CloudStorage", directoryHint: .isDirectory)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: storage, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let providers = children.filter { isFolder($0) }
            .map { CloudFolder(url: $0.standardizedFileURL, name: displayName(forFolderName: $0.lastPathComponent)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return found + providers
    }

    /// "GoogleDrive-me@example.com" becomes "Google Drive (me@example.com)", "OneDrive-Work" becomes
    /// "OneDrive (Work)", and a plain "Dropbox" stays "Dropbox".
    public static func displayName(forFolderName name: String) -> String {
        let known = ["GoogleDrive": "Google Drive", "OneDrive": "OneDrive", "Dropbox": "Dropbox", "Box": "Box", "ProtonDrive": "Proton Drive"]
        let parts = name.split(separator: "-", maxSplits: 1).map(String.init)
        guard let first = parts.first, let title = known[first] else { return name }
        guard parts.count == 2, !parts[1].isEmpty, parts[1] != first else { return title }
        return "\(title) (\(parts[1]))"
    }

    private static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// Files that are in the cloud but not yet on this Mac.
public enum OnlineStatus {
    /// macOS marks such a file "dataless": the name and size are here, the contents are not.
    static let datalessFlag: UInt32 = 0x4000_0000

    public static func isOnlineOnly(flags: UInt32) -> Bool {
        flags & datalessFlag != 0
    }

    public static func isOnlineOnly(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return isOnlineOnly(flags: info.st_flags)
    }

    /// Older iCloud stubs are hidden files named ".Report.pdf.icloud". Their real name is "Report.pdf".
    public static func realName(ofPlaceholder name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > 8 else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    /// The real size of the file, which an old stub keeps in a small property list.
    public static func size(ofPlaceholderAt url: URL) -> Int64? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let size = plist["NSURLFileSizeKey"] as? NSNumber else { return nil }
        return size.int64Value
    }
}

public enum CloudDownload {
    /// Brings an online-only file onto this Mac. Reading from it makes the provider fetch the
    /// contents, and the read waits until they arrive. iCloud files are asked for first.
    public static func materialize(_ url: URL) async throws {
        _ = try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        try await Task.detached {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            _ = try handle.read(upToCount: 1)
        }.value
    }
}
