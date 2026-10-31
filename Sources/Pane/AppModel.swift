import AppKit
import Foundation
import Observation
import PaneKit

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    private(set) var history: NavigationHistory
    private(set) var items: [FolderItem] = []
    var selection: Set<URL> = []
    private(set) var loadError: String?
    private(set) var isLoading = false
    /// True once a load has taken more than half a second.
    private(set) var isSlow = false
    var showHidden = false

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

    private let watcher = FolderWatcher()
    private var generation = 0
    private var reloadTask: Task<Void, Never>?

    var currentFolder: URL { history.current }
    var currentName: String { Locations.displayName(for: currentFolder) }
    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }
    var canGoUp: Bool { Breadcrumbs.parent(of: currentFolder) != nil }
    var selectedItems: [FolderItem] { items.filter { selection.contains($0.url) } }

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
        history = NavigationHistory(start: Self.canonical(start))
        afterNavigation()
    }

    // MARK: Navigating

    /// One spelling per folder, so the same folder reached two ways is equal.
    static func canonical(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path)
    }

    func go(to url: URL) {
        let url = Self.canonical(url)
        guard url != currentFolder else { return }
        history.visit(url)
        afterNavigation()
    }

    func goBack() {
        guard history.goBack() != nil else { return }
        afterNavigation()
    }

    func goForward() {
        guard history.goForward() != nil else { return }
        afterNavigation()
    }

    func goUp() {
        guard let parent = Breadcrumbs.parent(of: currentFolder) else { return }
        go(to: parent)
    }

    /// Return, Command-Down, or a double-click: a folder shows its contents, a file opens.
    func open(_ urls: [URL]) {
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        let chosen = items.filter { paths.contains($0.url.standardizedFileURL.path) }
        if chosen.count == 1, let only = chosen.first, only.isFolder {
            go(to: only.url)
            return
        }
        for item in chosen where !item.isFolder { openFile(item.url) }
    }

    func openSelection() {
        open(Array(selection))
    }

    private func openFile(_ url: URL) {
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            askForApp(for: url)
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func askForApp(for url: URL) {
        let alert = NSAlert()
        alert.messageText = "No app can open this file."
        alert.informativeText = "\(url.lastPathComponent) has no app to open it."
        alert.addButton(withTitle: "Choose App…")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        guard panel.runModal() == .OK, let app = panel.url else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private func afterNavigation() {
        selection = []
        isEditingAddress = false
        syncTree()
        Prefs.defaults.set(currentFolder.path, forKey: "pane.folder")
        watcher.watch(currentFolder) { [weak self] in self?.scheduleReload() }
        reload()
    }

    // MARK: Listing

    func reload() {
        let folder = currentFolder
        let hidden = showHidden
        generation += 1
        let mine = generation
        isLoading = true
        isSlow = false
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            if mine == generation, isLoading { isSlow = true }
        }
        Task {
            let result = await Task.detached { Result { try FolderLister.list(folder, showHidden: hidden) } }.value
            guard mine == generation else { return }
            isLoading = false
            isSlow = false
            switch result {
            case .success(let listed):
                items = listed
                loadError = nil
                let still = Set(listed.map(\.url))
                selection = selection.intersection(still)
            case .failure:
                items = []
                loadError = "Unable to read this folder."
            }
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .seconds(0.2))
            if !Task.isCancelled { reload() }
        }
    }

    // MARK: Navigation pane

    /// Expands the folders above the current one and selects its row.
    private func syncTree() {
        let url = currentFolder
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
        let path = currentFolder.path
        addressText = path == home ? "~" : (path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
        addressFailedText = nil
        isEditingAddress = true
    }

    func cancelEditingAddress() {
        isEditingAddress = false
        addressFailedText = nil
    }

    func commitAddress() {
        switch PathResolver.resolve(addressText, home: Locations.home, base: currentFolder) {
        case .success(let url):
            isEditingAddress = false
            addressFailedText = nil
            go(to: url)
        case .failure(.empty):
            cancelEditingAddress()
        case .failure:
            addressFailedText = addressText
        }
    }
}
