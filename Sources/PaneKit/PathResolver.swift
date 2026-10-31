import Foundation

/// Turns what a person types in the Address bar into a folder.
public enum PathResolver {
    public enum Failure: Error, Equatable, Sendable {
        case empty
        case notFound
        case notAFolder
    }

    /// `~` and `~/Documents` start at `home`. A path with no leading slash
    /// starts at `base`. Quotes and backslash-spaces are removed.
    public static func resolve(_ text: String, home: URL, base: URL) -> Result<URL, Failure> {
        var path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.count >= 2, let first = path.first, first == path.last, first == "\"" || first == "'" {
            path = String(path.dropFirst().dropLast())
        }
        path = path.replacingOccurrences(of: "\\ ", with: " ")
        guard !path.isEmpty else { return .failure(.empty) }

        let url: URL
        if path == "~" {
            url = home
        } else if path.hasPrefix("~/") {
            url = home.appending(path: String(path.dropFirst(2)))
        } else if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = base.appending(path: path)
        }
        let standard = url.standardizedFileURL

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standard.path, isDirectory: &isDirectory) else {
            return .failure(.notFound)
        }
        guard isDirectory.boolValue else { return .failure(.notAFolder) }
        return .success(standard)
    }
}

/// The folders from the root down to a folder, for the Address bar.
public enum Breadcrumbs {
    public static func chain(for url: URL) -> [URL] {
        var result: [URL] = []
        var current = url.standardizedFileURL
        while true {
            result.append(current)
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { break }
            current = parent
        }
        return result.reversed()
    }

    /// The folder above, or nil at the root.
    public static func parent(of url: URL) -> URL? {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        return parent.path == url.standardizedFileURL.path ? nil : parent
    }
}
