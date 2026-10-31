import Foundation
import Observation
import PaneKit
import SwiftUI

enum ViewMode: String, CaseIterable {
    case details, list, icons

    var title: String {
        switch self {
        case .details: "Details"
        case .list: "List"
        case .icons: "Icons"
        }
    }

    var symbol: String {
        switch self {
        case .details: "list.bullet"
        case .list: "list.dash"
        case .icons: "square.grid.2x2"
        }
    }
}

/// How folders are shown, for every tab: the sort and whether folders come first.
/// Saved between launches. Later stories add hidden files, extensions, and the view mode.
@Observable
final class ViewSettings {
    var mode: ViewMode { didSet { changed() } }
    var sortKey: SortKey { didSet { changed() } }
    var ascending: Bool { didSet { changed() } }
    var foldersFirst: Bool { didSet { changed() } }
    /// Dotfiles and other hidden items. Off by default.
    var showHidden: Bool { didSet { changed() } }
    /// Show ".pdf" after names. On by default, so a name is never ambiguous.
    var showExtensions: Bool { didSet { changed() } }
    /// Which columns show, and their order and widths, saved for each folder as JSON.
    private(set) var columnData: [String: Data]
    /// Called after any change, so open tabs can re-sort.
    var onChange: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = Prefs.defaults) {
        self.defaults = defaults
        columnData = defaults.dictionary(forKey: "view.columns") as? [String: Data] ?? [:]
        mode = ViewMode(rawValue: defaults.string(forKey: "view.mode") ?? "") ?? .details
        sortKey = SortKey(rawValue: defaults.string(forKey: "view.sortKey") ?? "") ?? .name
        ascending = defaults.object(forKey: "view.ascending") as? Bool ?? true
        foldersFirst = defaults.object(forKey: "view.foldersFirst") as? Bool ?? true
        showHidden = defaults.object(forKey: "view.showHidden") as? Bool ?? false
        showExtensions = defaults.object(forKey: "view.showExtensions") as? Bool ?? true
    }

    /// A click on a column header: the same column flips the direction, a new one starts ascending.
    func setSort(_ key: SortKey, ascending: Bool) {
        sortKey = key
        self.ascending = ascending
    }

    /// The column layout for a folder, or the default one when none was saved.
    func columns(for folder: URL) -> TableColumnCustomization<FolderItem> {
        guard let data = columnData[folder.standardizedFileURL.path],
              let saved = try? JSONDecoder().decode(TableColumnCustomization<FolderItem>.self, from: data) else {
            return TableColumnCustomization<FolderItem>()
        }
        return saved
    }

    func setColumns(_ layout: TableColumnCustomization<FolderItem>, for folder: URL) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        let key = folder.standardizedFileURL.path
        guard columnData[key] != data else { return }
        // A layout is small, but keep the saved set from growing without end.
        if columnData.count >= 300, columnData[key] == nil, let oldest = columnData.keys.first { columnData[oldest] = nil }
        columnData[key] = data
        defaults.set(columnData, forKey: "view.columns")
    }

    func reset() {
        columnData = [:]
        mode = .details
        sortKey = .name
        ascending = true
        foldersFirst = true
        showHidden = false
        showExtensions = true
    }

    private func changed() {
        defaults.set(mode.rawValue, forKey: "view.mode")
        defaults.set(sortKey.rawValue, forKey: "view.sortKey")
        defaults.set(ascending, forKey: "view.ascending")
        defaults.set(foldersFirst, forKey: "view.foldersFirst")
        defaults.set(showHidden, forKey: "view.showHidden")
        defaults.set(showExtensions, forKey: "view.showExtensions")
        onChange?()
    }
}
