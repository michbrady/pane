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

    // Connect to Server
    var showConnectSheet = false
    private(set) var isConnecting = false
    private(set) var connectError: String?
    private(set) var recentServers = RecentServers(Prefs.defaults.stringArray(forKey: "pane.recentServers") ?? [])
    /// The real mount and Keychain calls. Tests swap them, so they never reach a network or your Keychain.
    var mounter: (SMBAddress, String?, String?) async -> Result<URL, MountFailure> = { await SMBMount.mount($0, user: $1, password: $2) }
    var savePassword: (String, String, String) -> Void = { PasswordKeychain.save($0, server: $1, account: $2) }
    var savedPassword: (String, String) -> String? = { PasswordKeychain.password(server: $0, account: $1) }

    /// The items whose Properties panel is open.
    private(set) var propertiesURLs: [URL]?

    // Navigation pane
    private(set) var quickRoots: [NavNode]
    private var pins: PinStore
    let homeRoot: NavNode
    private(set) var driveRoots: [NavNode] = []
    private(set) var networkRoots: [NavNode] = []
    /// iCloud Drive and the cloud services installed on this Mac.
    private(set) var cloudRoots: [NavNode] = []
    var thisMacRoots: [NavNode] { [homeRoot] + driveRoots }
    /// Where the mounted volumes come from. Tests use a fake list, so they see the same on every Mac.
    var volumeSource: () -> [VolumeInfo] = { Locations.isOverridden ? [] : VolumeInfo.mounted() }
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
        homeRoot = NavNode(url: Locations.home, prefix: "home:")
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
        refreshVolumes()
        if !Locations.isOverridden {
            // A drive or share appeared, went away, or was renamed.
            for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
                NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshVolumes() }
                }
            }
        }
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
        // The root that holds this folder: the home folder, a drive, or a share. The deepest one wins.
        let roots: [(prefix: String, path: String)] =
            [("home:", Locations.home.path)] + driveRoots.map { ("vol:", $0.url.path) } + networkRoots.map { ("net:", $0.url.path) }
            + cloudRoots.map { ("cloud:", $0.url.path) } + [("vol:", "/")]
        let holder = roots.filter { url.path == $0.path || url.path.hasPrefix($0.path == "/" ? "/" : $0.path + "/") }
            .max { $0.path.count < $1.path.count } ?? ("vol:", "/")
        let pinned = quickRoots.contains { $0.url.path == url.path }
        navSelection = pinned ? "quick:" + url.path : holder.prefix + url.path
        for ancestor in Breadcrumbs.chain(for: url).dropLast()
        where ancestor.path.count >= holder.path.count && (ancestor.path == holder.path || ancestor.path.hasPrefix(holder.path == "/" ? "/" : holder.path + "/")) {
            expanded.insert(holder.prefix + ancestor.path)
        }
    }

    // MARK: Connect to Server

    func openConnectSheet() {
        connectError = nil
        showConnectSheet = true
    }

    func closeConnectSheet() {
        showConnectSheet = false
        connectError = nil
    }

    /// For snapshots: fills the recent list without connecting.
    func recentServersForSnapshot(_ servers: [String]) {
        for server in servers.reversed() { recentServers.add(server) }
    }

    func clearRecentServers() {
        recentServers.clear()
        Prefs.defaults.set(recentServers.items, forKey: "pane.recentServers")
    }

    /// Connect: check the address, mount the share, then show it. A failure keeps the sheet open and says why.
    func connect(address text: String, user: String, password: String, remember: Bool) {
        guard !isConnecting else { return }
        let address: SMBAddress
        switch SMBAddress.parse(text) {
        case .success(let parsed): address = parsed
        case .failure(.empty): connectError = "Type a server address, like smb://nas/photos."; return
        case .failure(.notSMB): connectError = "The address has to start with smb://."; return
        case .failure(.noHost): connectError = "Add the server name after smb://."; return
        }
        connectError = nil
        isConnecting = true
        let account = user.isEmpty ? (address.user ?? "") : user
        Task {
            // A password saved earlier is used when the field is left empty.
            let secret = password.isEmpty && !account.isEmpty ? savedPassword(address.host, account) ?? "" : password
            let result = await mounter(address, account, secret)
            isConnecting = false
            switch result {
            case .success(let mountpoint):
                recentServers.add(address.displayText)
                Prefs.defaults.set(recentServers.items, forKey: "pane.recentServers")
                if remember, !account.isEmpty, !secret.isEmpty { savePassword(secret, address.host, account) }
                showConnectSheet = false
                refreshVolumes()
                tab.go(to: mountpoint)
            case .failure(let failure):
                connectError = ConnectionError.message(forCode: failure.code)
            }
        }
    }

    // MARK: Drives and shares

    /// Reads the mounted volumes again: drives go under This Mac and shares under Network.
    func refreshVolumes() {
        let sections = VolumeSections.split(volumeSource())
        driveRoots = sections.drives.map { NavNode(url: $0.url, prefix: "vol:", name: $0.name, ejectable: $0.isEjectable) }
        networkRoots = sections.network.map { NavNode(url: $0.url, prefix: "net:", name: $0.name, ejectable: true) }
        let cloud = CloudLocations.list(home: Locations.home)
        Locations.cloudNames = Dictionary(uniqueKeysWithValues: cloud.map { ($0.url.path, $0.name) })
        cloudRoots = cloud.map { NavNode(url: $0.url, prefix: "cloud:", name: $0.name) }
        // A tab showing a folder on a volume that just went away says so.
        for tab in tabs where !FileManager.default.fileExists(atPath: tab.currentFolder.path) { tab.reload() }
        syncTree()
    }

    /// The eject button beside a drive or share. A busy volume says so and stays.
    func eject(_ node: NavNode) {
        let url = node.url
        let name = node.name
        if tab.currentFolder.path.hasPrefix(url.path) { tab.go(to: Locations.home) }
        Task {
            do {
                try await Task.detached { try NSWorkspace.shared.unmountAndEjectDevice(at: url) }.value
            } catch {
                actions.alertMessage = "Unable to eject \u{201C}\(name)\u{201D}. Items are in use."
            }
            refreshVolumes()
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