import AppKit
import Foundation
import Observation
import PaneKit

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let tab: FolderTab
    let actions = FileActions()

    // Navigation pane
    let quickRoots: [NavNode]
    let thisMacRoots: [NavNode]
    var expanded: Set<String> {
        didSet { Prefs.defaults.set(Array(expanded), forKey: "pane.expanded") }
    }
    var navSelection: String?

    // Address bar
    var isEditingAddress = false
    var addressText = ""
    /// The text that did not resolve. The error shows while the field still holds it.
    private(set) var addressFailedText: String?
    var addressError: String? {
        addressFailedText != nil && addressFailedText == addressText ? "No folder at this path." : nil
    }

    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Locations.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }
    init() {
        let defaults = Prefs.defaults
        quickRoots = Locations.quickAccess.map { NavNode(url: $0, prefix: "quick:") }
        thisMacRoots = [NavNode(url: Locations.home, prefix: "home:")]
            + Locations.volumes.map { NavNode(url: $0, prefix: "vol:") }
        expanded = Set(defaults.stringArray(forKey: "pane.expanded") ?? [])

        let env = ProcessInfo.processInfo.environment
        var start = Locations.home.appending(path: "Downloads", directoryHint: .isDirectory)
        if let path = env["APP_START"], !path.isEmpty {
            start = URL(fileURLWithPath: path)
        } else if defaults.object(forKey: "reopenLastFolder") as? Bool ?? true,
                  let saved = defaults.string(forKey: "pane.folder"),
                  FileManager.default.fileExists(atPath: saved) {
            start = URL(fileURLWithPath: saved)
        } else if !FileManager.default.fileExists(atPath: start.path) {
            start = Locations.home
        }
        tab = FolderTab(start: start)
        tab.didNavigate = { [unowned self] in
            isEditingAddress = false
            syncTree()
            Prefs.defaults.set(tab.currentFolder.path, forKey: "pane.folder")
        }
        actions.tabProvider = { [unowned self] in tab }
        tab.begin()
    }

    /// Cut and Copy work on a selection, or on the text in the Address bar.
    var canCopy: Bool { !tab.selection.isEmpty || isEditingAddress }


    // MARK: Navigation pane

    /// Expands the folders above the current one and selects its row.
    private func syncTree() {
        let url = tab.currentFolder
        let pinned = quickRoots.contains { $0.url.path == url.path }
        let homePath = Locations.home.path
        let underHome = url.path == homePath || url.path.hasPrefix(homePath + "/")
        let prefix = underHome ? "home:" : "vol:"
        navSelection = pinned ? "quick:" + url.path : prefix + url.path
        let floor = underHome ? homePath : "/"
        for ancestor in Breadcrumbs.chain(for: url).dropLast()
        where ancestor.path.count >= floor.count && (ancestor.path == floor || ancestor.path.hasPrefix(floor == "/" ? "/" : floor + "/")) {
            expanded.insert(prefix + ancestor.path)
        }
    }

    /// Row id to folder, for a click in the Navigation pane.
    static func url(forNavID id: String) -> URL? {
        guard let colon = id.firstIndex(of: ":") else { return nil }
        return URL(fileURLWithPath: String(id[id.index(after: colon)...]))
    }

    // MARK: Address bar

    func beginEditingAddress() {
        let home = Locations.home.path
        let path = tab.currentFolder.path
        addressText = path == home ? "~" : (path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
        addressFailedText = nil
        isEditingAddress = true
    }

    func cancelEditingAddress() {
        isEditingAddress = false
        addressFailedText = nil
    }

    func commitAddress() {
        switch PathResolver.resolve(addressText, home: Locations.home, base: tab.currentFolder) {
        case .success(let url):
            isEditingAddress = false
            addressFailedText = nil
            tab.go(to: url)
        case .failure(.empty):
            cancelEditingAddress()
        case .failure:
            addressFailedText = addressText
        }
    }
}