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

    /// True while the first-run Full Disk Access screen shows.
    private(set) var showFullDiskAccessGuide = false

    func dismissFullDiskAccessGuide(openSettings: Bool = false) {
        showFullDiskAccessGuide = false
        Prefs.defaults.set(true, forKey: "pane.fdaGuideShown")
        if openSettings { Permissions.openFullDiskAccess() }
    }

    /// For snapshots: shows the screen without checking the real permission.
    func showFullDiskAccessGuideForSnapshot() { showFullDiskAccessGuide = true }

    // Open folders for other apps
    /// What opens folders for other apps. Tests use an in-memory stand-in, so they never change your Mac.
    var folderHandlerSystem: FolderHandlerSystem = Locations.isOverridden ? InMemoryFolderHandlerSystem() : SystemFolderHandler()
    private(set) var folderHandlerState: FolderHandlerState = {
        Prefs.defaults.data(forKey: "pane.folderHandlerState").flatMap { try? JSONDecoder().decode(FolderHandlerState.self, from: $0) } ?? FolderHandlerState()
    }()
    var usePaneForFolders: Bool { folderHandlerState.isOn }

    let connections = Connections()

    /// The items whose Properties panel is open.
    private(set) var propertiesURLs: [URL]?

    let places = Places()
    /// The open connections to servers, shared by every tab.
    let router = FileSystemRouter()

    // Address bar
    var isEditingAddress = false
    var addressText = ""
    /// The text that did not resolve. The error shows while the field still holds it.
    private(set) var addressFailedText: String?
    private var addressMessage = "No folder at this path."
    var addressError: String? {
        addressFailedText != nil && addressFailedText == addressText ? addressMessage : nil
    }

    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Locations.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }
    init() {
        let defaults = Prefs.defaults
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
        places.currentFolder = { [unowned self] in tab.currentFolder }
        places.goTo = { [unowned self] url in tab.go(to: url) }
        places.volumesChanged = { [unowned self] in
            // A tab showing a folder on a volume that just went away says so.
            for tab in tabs where !FileManager.default.fileExists(atPath: tab.currentFolder.path) { tab.reload() }
        }
        places.alert = { [unowned self] message in actions.alertMessage = message }
        places.serverKeys = { [unowned self] in router.serverKeys }
        places.disconnect = { [unowned self] key in disconnect(serverKey: key) }
        connections.didMount = { [unowned self] mountpoint in
            places.refreshVolumes()
            tab.go(to: mountpoint)
        }
        places.start()
        GlobalHotKey.shared.onPress = { [unowned self] in globalShortcutPressed() }
        GlobalHotKey.shared.start()
        // Tests and snapshots never ask. A person gets the screen once, if Pane lacks access.
        if !Locations.isOverridden {
            showFullDiskAccessGuide = FullDiskAccessGuide.shouldShow(
                granted: Permissions.hasFullDiskAccess, shownBefore: defaults.bool(forKey: "pane.fdaGuideShown"))
        }
    }

    // MARK: Tabs

    private func makeTab(start: URL) -> FolderTab {
        let tab = FolderTab(start: start, view: view)
        tab.spotlight = Locations.isOverridden ? nil : SystemSpotlight()
        tab.router = router
        tab.requestRemoteOpen = { [unowned self] _ in actions.alertMessage = "Opening a file on a server comes in a later step. For now, browse it." }
        tab.requestDownload = { [unowned self] url in actions.downloadAndOpen(url) }
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
        places.refreshPins()
        places.syncTree()
        saveTabs()
    }

    private func saveTabs() {
        let defaults = Prefs.defaults
        // A server is not reconnected at launch, so a tab on one is saved as the home folder.
        let saved = { (tab: FolderTab) in tab.isRemote ? Locations.home.path : tab.currentFolder.path }
        defaults.set(tabs.map(saved), forKey: "pane.tabs")
        defaults.set(activeIndex, forKey: "pane.activeTab")
        defaults.set(saved(tab), forKey: "pane.folder")
    }

    /// Cut and Copy work on a selection, or on the text in the Address bar.
    var canCopy: Bool { !tab.selection.isEmpty || isEditingAddress }


    // MARK: Servers

    /// A server is connected: file it in the router and show it under Connections.
    func connected(_ server: any RemoteFileSystem) {
        router.register(server)
        places.refreshConnections()
    }

    /// Eject on a server's row: close the connection and take it off the list.
    func disconnect(serverKey: String) {
        let server = router.remote(for: URL(string: serverKey + "/")!)
        router.remove(serverKey: serverKey)
        for tab in tabs where tab.isRemote && RemoteURL.serverKey(tab.currentFolder) == serverKey { tab.go(to: Locations.home) }
        places.refreshConnections()
        Task { await server?.disconnect() }
    }

    // MARK: Global shortcut

    /// The shortcut was pressed in any app: bring Pane forward with a new tab at the home folder.
    func globalShortcutPressed() {
        NSApp.activate()
        newTab(at: Locations.home)
    }

    // MARK: Terminal

    /// Opens Terminal in a folder: the selected folder, else the folder shown.
    func openInTerminal(_ folder: URL? = nil) {
        let target = folder ?? OpenInTerminal.folder(selected: tab.selectedItems, current: tab.currentFolder)
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            actions.alertMessage = "Terminal was not found on this Mac."
            return
        }
        NSWorkspace.shared.open([target], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    /// True when Terminal is installed.
    var canOpenInTerminal: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") != nil }

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

    // MARK: Opening folders for other apps

    /// Settings > "Use Pane to open folders". On remembers what was set before, and off puts it back.
    func setUsePaneForFolders(_ on: Bool) async {
        var state = folderHandlerState
        if on {
            await FolderHandlerSwitch.turnOn(folderHandlerSystem, as: Bundle.main.bundleIdentifier ?? "com.michaelbrady.pane", state: &state)
        } else {
            await FolderHandlerSwitch.turnOff(folderHandlerSystem, state: &state)
        }
        folderHandlerState = state
        Prefs.defaults.set(try? JSONEncoder().encode(state), forKey: "pane.folderHandlerState")
    }

    /// Another app asked Pane to open something, like Show in Finder from a download. A folder opens.
    /// A file shows in its folder, selected. Any further items open in their own tabs.
    func openFromOutside(_ urls: [URL]) {
        guard let first = urls.first else { return }
        NSApp.activate()
        show(first, inNewTab: false)
        for url in urls.dropFirst() { show(url, inNewTab: true) }
    }

    private func show(_ url: URL, inNewTab: Bool) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        let folder = isDirectory.boolValue ? url : url.deletingLastPathComponent()
        if inNewTab { newTab(at: folder) } else { tab.go(to: folder) }
        guard !isDirectory.boolValue else { return }
        let path = url.standardizedFileURL.path
        tab.afterReload = { [tab] in
            if let item = tab.items.first(where: { $0.url.standardizedFileURL.path == path }) { tab.selection = [item.url] }
        }
    }

    // MARK: Address bar

    func beginEditingAddress() {
        let home = Locations.home.path
        let path = tab.currentFolder.path
        if tab.isRemote {
            addressText = tab.currentFolder.absoluteString.removingPercentEncoding ?? tab.currentFolder.absoluteString
        } else {
            addressText = path == home ? "~" : (path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
        }
        addressFailedText = nil
        isEditingAddress = true
    }

    func cancelEditingAddress() {
        isEditingAddress = false
        addressFailedText = nil
    }

    func commitAddress() {
        // A server address, like sftp://nas/Documents. It needs an open connection.
        if let remote = RemoteURL.parse(addressText) {
            guard router.remote(for: remote) != nil else {
                addressMessage = "Not connected to that server. Use Go > Connect to Server."
                addressFailedText = addressText
                return
            }
            isEditingAddress = false
            addressFailedText = nil
            tab.go(to: remote)
            return
        }
        addressMessage = "No folder at this path."
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