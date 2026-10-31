import Foundation
import Observation
import PaneKit

/// How folders are shown, for every tab: the sort and whether folders come first.
/// Saved between launches. Later stories add hidden files, extensions, and the view mode.
@Observable
final class ViewSettings {
    var sortKey: SortKey { didSet { changed() } }
    var ascending: Bool { didSet { changed() } }
    var foldersFirst: Bool { didSet { changed() } }
    /// Called after any change, so open tabs can re-sort.
    var onChange: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = Prefs.defaults) {
        self.defaults = defaults
        sortKey = SortKey(rawValue: defaults.string(forKey: "view.sortKey") ?? "") ?? .name
        ascending = defaults.object(forKey: "view.ascending") as? Bool ?? true
        foldersFirst = defaults.object(forKey: "view.foldersFirst") as? Bool ?? true
    }

    /// A click on a column header: the same column flips the direction, a new one starts ascending.
    func setSort(_ key: SortKey, ascending: Bool) {
        sortKey = key
        self.ascending = ascending
    }

    func reset() {
        sortKey = .name
        ascending = true
        foldersFirst = true
    }

    private func changed() {
        defaults.set(sortKey.rawValue, forKey: "view.sortKey")
        defaults.set(ascending, forKey: "view.ascending")
        defaults.set(foldersFirst, forKey: "view.foldersFirst")
        onChange?()
    }
}
