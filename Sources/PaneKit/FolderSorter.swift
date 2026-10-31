import Foundation

public enum SortKey: String, Sendable, CaseIterable {
    case name, modified, kind, size
}

/// Orders a folder listing for the column headers.
public enum FolderSorter {
    /// Names sort naturally ("file2" before "file10"). Size sorts by bytes. With `foldersFirst`
    /// the folders stay on top for every column, each group in the chosen order.
    public static func sorted(_ items: [FolderItem], key: SortKey, ascending: Bool, foldersFirst: Bool) -> [FolderItem] {
        items.sorted { a, b in
            if foldersFirst, a.isFolder != b.isFolder { return a.isFolder }
            let order = compare(a, b, key: key)
            if order == .orderedSame { return false }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    private static func compare(_ a: FolderItem, _ b: FolderItem, key: SortKey) -> ComparisonResult {
        func byName() -> ComparisonResult { a.name.localizedStandardCompare(b.name) }
        switch key {
        case .name:
            return byName()
        case .modified:
            let x = a.modified ?? .distantPast, y = b.modified ?? .distantPast
            return x == y ? byName() : (x < y ? .orderedAscending : .orderedDescending)
        case .kind:
            let order = a.kind.localizedStandardCompare(b.kind)
            return order == .orderedSame ? byName() : order
        case .size:
            let x = a.size ?? -1, y = b.size ?? -1
            return x == y ? byName() : (x < y ? .orderedAscending : .orderedDescending)
        }
    }
}

public extension FolderItem {
    /// Non-optional values for the Table's sortable columns.
    var sortModified: Date { modified ?? .distantPast }
    var sortSize: Int64 { size ?? -1 }
}

public extension FolderItem {
    /// The name as shown. With extensions off, "Budget.xlsx" shows as "Budget". Folders and
    /// names like ".gitignore" show whole. Renaming and sorting always use the full name.
    func displayName(showExtensions: Bool) -> String {
        let ext = (name as NSString).pathExtension
        guard !showExtensions, !isFolder, !ext.isEmpty, name.count > ext.count + 1 else { return name }
        return String(name.dropLast(ext.count + 1))
    }
}
