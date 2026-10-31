import AppKit
import Foundation

/// Where Pane starts and which places the Navigation pane lists.
///   APP_HOME=<dir> Pane     treat <dir> as the home folder, and use throwaway settings
///                           (tests and snapshots, so they never touch your files or settings)
enum Locations {
    /// True when APP_HOME points somewhere else (tests, snapshots).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_HOME"] ?? "").isEmpty
    }

    static var home: URL {
        if let path = ProcessInfo.processInfo.environment["APP_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    /// The folders pinned at first.
    static var quickAccess: [URL] {
        ["Desktop", "Downloads", "Documents", "Pictures"]
            .map { home.appending(path: $0, directoryHint: .isDirectory).standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The startup disk and any mounted drives. Tests list none, to stay the same on every Mac.
    static var volumes: [URL] {
        guard !isOverridden else { return [] }
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        let others = mounted.map(\.standardizedFileURL).filter { $0.path != "/" && !$0.path.hasPrefix("/System/Volumes") }
        return [URL(fileURLWithPath: "/")] + others
    }

    static func displayName(for url: URL) -> String {
        if url.path == "/" { return FileManager.default.displayName(atPath: "/") }
        if url.path == home.path, !isOverridden { return NSUserName() }
        return FileManager.default.displayName(atPath: url.path)
    }
}

/// Settings Pane remembers. Tests use their own suite, never your real settings.
enum Prefs {
    static var defaults: UserDefaults {
        Locations.isOverridden ? UserDefaults(suiteName: "com.michaelbrady.pane.test") ?? .standard : .standard
    }
}

/// File icons from the system. Files share one icon per extension, so a big
/// folder does not ask for thousands of icons.
@MainActor
enum IconCache {
    private static var byKey: [String: NSImage] = [:]

    static func icon(for url: URL, isFolder: Bool) -> NSImage {
        let key: String
        if isFolder {
            key = "folder"
        } else if url.pathExtension.isEmpty || ["app", "icns", "dmg", "pkg"].contains(url.pathExtension.lowercased()) {
            key = url.path
        } else {
            key = "." + url.pathExtension.lowercased()
        }
        if let cached = byKey[key] { return cached }
        let image = isFolder
            ? NSWorkspace.shared.icon(for: .folder)
            : NSWorkspace.shared.icon(forFile: url.path)
        byKey[key] = image
        return image
    }
}
