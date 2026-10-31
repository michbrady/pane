import Foundation

/// Finder tags: read and change the names on files and folders.
public enum TagEditor {
    /// The seven color tags Finder offers, in its order.
    public static let standard = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"]

    public static func tags(of url: URL) -> [String] {
        (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }

    public static func set(_ names: [String], on url: URL) throws {
        var values = URLResourceValues()
        values.tagNames = names
        var mutable = url
        try mutable.setResourceValues(values)
    }

    /// Adds or removes one tag on every item. Items that already match are left alone.
    /// Returns the items that could not be changed.
    @discardableResult
    public static func apply(_ name: String, to urls: [URL], add: Bool) -> [URL] {
        var failed: [URL] = []
        for url in urls {
            var names = tags(of: url)
            let has = names.contains(name)
            guard has != add else { continue }
            if add { names.append(name) } else { names.removeAll { $0 == name } }
            do { try set(names, on: url) } catch { failed.append(url) }
        }
        return failed
    }

    @discardableResult
    public static func removeAll(from urls: [URL]) -> [URL] {
        urls.filter { url in
            guard !tags(of: url).isEmpty else { return false }
            return (try? set([], on: url)) == nil
        }
    }
}
