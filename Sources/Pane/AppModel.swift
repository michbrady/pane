import AppKit
import Foundation
import Observation
import PaneKit

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let view = ViewSettings()
    /// The open tabs. Each is one folder with its own history, listing, and selection.
    private(set) var tabs: [FolderTab] = []
    private(set) var activeIndex = 0
    var tab: FolderTab { tabs[activeIndex] }
    let actions = FileActions()

    /// Cmd-F and F3 add one, and the Search box takes the focus.
    private(set) var searchFocusRequests = 0

    func focusSearch() { searchFocusRequests += 1 }

    /// The items whose Properties panel is open.
    private(set) var propertiesURLs: [URL]?

    // Navigation pane
    private(set) var quickRoots: [NavNode]
    private var pins: PinStore
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
        let store = PinStore(saved: defaults.array(forKey: "pane.pins") as? [Data], defaults: Locations.quickAccess)
        pins = store
        quickRoots = store.urls.map { NavNode(url: $0, prefix: "quick:") }
        thisMacRoots = [NavNode(url: Locations.home, prefix: "home:")]
            + Locations.volumes.map { NavNode(url: $0, prefix: "vol:") }
        expanded = Set(defaults.stringArray(forKey: "pane.expanded") ?? [])

        let env = ProcessInfo.processInfo.environment
        var starts: [URL] = []
        var active = 0
        if let path = env["APP_START"], !path.isEmpty {
            starts = [URL(fileURLWithPath: path)]
        } else if defaults.object(forKey: "reopenLastFolder") as? Bool ?? true {
            // Reopen the tabs from last time, skipping folders that are gone.
            let saved = defaults.stringArray(forKey: "pane.tabs") ?? defaults.string(forKey: "pane.folder").map { [$0] } ?? []
            starts = saved.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
            active = min(defaults.integer(forKey: "pane.activeTab"), max(starts.count - 1, 0))
        }
        if starts.isEmpty {
            let downloads = Locations.home.appending(path: "Downloads", directoryHint: .isDirectory)
            starts = [FileManager.default.fileExists(atPath: downloads.path) ? downloads : Locations.home]
        }
        view.onChange = { [unowned self] in for tab in tabs { tab.viewSettingsChanged() } }
        actions.tabProvider = { [unowned self] in tab }
        tabs = starts.map { makeTab(start: $0) }
        activeIndex = active
        for tab in tabs { tab.begin() }
        activated()
    }

    // MARK: Tabs

    private func makeTab(start: URL) -> FolderTab {
        let tab = FolderTab(start: start, view: view)
        tab.spotlight = Locations.isOverridden ? nil : SystemSpotlight()
        tab.didNavigate = { [unowned self, unowned tab] in
            // A tab in the background changes nothing outside itself.
            if tab === self.tab { activated() } else { saveTabs() }
        }
        return tab
    }

    /// Opens a folder in a new tab, next to the current one, and shows it.
    func newTab(at url: URL? = nil, activate: Bool = true) {
        let tab = makeTab(start: url ?? self.tab.currentFolder)
        tabs.insert(tab, at: activeIndex + 1)
        tab.begin()
        if activate { select(tabs.firstIndex { $0 === tab } ?? activeIndex) } else { saveTabs() }
    }

    func select(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeIndex = index
        activated()
    }

    func selectNextTab() { select((activeIndex + 1) % tabs.count) }
    func selectPreviousTab() { select((activeIndex - 1 + tabs.count) % tabs.count) }

    /// Closes a tab. The last tab is not closed here: the window closes instead (returns false).
    @discardableResult
    func close(_ tab: FolderTab) -> Bool {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0 === tab }) else { return false }
        let wasActive = index == activeIndex
        tabs.remove(at: index)
        if index < activeIndex { activeIndex -= 1 }
        activeIndex = min(activeIndex, tabs.count - 1)
        if wasActive { activated() } else { saveTabs() }
        return true
    }

    func closeOtherTabs(except tab: FolderTab) {
        guard let keep = tabs.firstIndex(where: { $0 === tab }) else { return }
        tabs = [tabs[keep]]
        activeIndex = 0
        activated()
    }

    /// What changes when the shown tab changes or navigates: the tree, the Address bar, saved state.
    private func activated() {
        isEditingAddress = false
        refreshPins()
        syncTree()
        saveTabs()
    }

    private func saveTabs() {
        let defaults = Prefs.defaults
        defaults.set(tabs.map { $0.currentFolder.path }, forKey: "pane.tabs")
        defaults.set(activeIndex, forKey: "pane.activeTab")
        defaults.set(tab.currentFolder.path, forKey: "pane.folder")
    }

    /// Cut and Copy work on a selection, or on the text in the Address bar.
    var canCopy: Bool { !tab.selection.isEmpty || isEditingAddress }


    // MARK: Quick Look

    /// Space: open Quick Look for the selected items, or close it if it is open.
    func toggleQuickLook() {
        let controller = QuickLookController.shared
        controller.model = self
        if controller.isShown {
            controller.close()
        } else {
            controller.show(tab.selectedItems.map(\.url))
        }
    }

    // MARK: Tags

    func tags(of url: URL) -> [String] {
        let path = url.standardizedFileURL.path
        return tab.items.first { $0.url.standardizedFileURL.path == path }?.tags ?? TagEditor.tags(of: url)
    }

    /// The tags every one of these items has.
    func commonTags(of urls: [URL]) -> Set<String> {
        guard let first = urls.first else { return [] }
        return urls.dropFirst().reduce(Set(tags(of: first))) { $0.intersection(tags(of: $1)) }
    }

    func setTag(_ name: String, on urls: [URL], add: Bool) {
        let failed = TagEditor.apply(name, to: urls, add: add)
        if let first = failed.first { actions.alertMessage = "Unable to change the tags on \(first.lastPathComponent)." }
        tab.reload()
    }

    func removeAllTags(from urls: [URL]) {
        let failed = TagEditor.removeAll(from: urls)
        if let first = failed.first { actions.alertMessage = "Unable to change the tags on \(first.lastPathComponent)." }
        tab.reload()
    }

    // MARK: Properties

    /// Cmd-I: the selected items, or the folder being shown when nothing is selected.
    func showProperties() {
        let urls = Array(tab.selection)
        propertiesURLs = urls.isEmpty ? [tab.currentFolder] : urls
    }

    func closeProperties() {
        propertiesURLs = nil
    }

    // MARK: Quick access

    func isPinned(_ url: URL) -> Bool { pins.contains(url) }

    func pin(_ url: URL, at index: Int? = nil) {
        pins.pin(url, at: index)
        pinsChanged()
    }

    func unpin(_ url: URL) {
        pins.unpin(url)
        pinsChanged()
    }

    private func pinsChanged() {
        Prefs.defaults.set(pins.bookmarks, forKey: "pane.pins")
        refreshPins()
        syncTree()
    }

    /// Rebuilds the Quick access rows when a pinned folder was renamed or moved.
    private func refreshPins() {
        let urls = pins.urls
        guard urls.map(\.path) != quickRoots.map(\.url.path) else { return }
        quickRoots = urls.map { NavNode(url: $0, prefix: "quick:") }
    }

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