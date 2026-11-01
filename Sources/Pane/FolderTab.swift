import AppKit
import Foundation
import Observation
import PaneKit

/// One open folder: its history, listing, selection, and watcher.
/// Tabs (S-026) make one of these per tab.
@Observable
final class FolderTab: Identifiable {
    let id = UUID()
    private(set) var history: NavigationHistory
    private(set) var items: [FolderItem] = []
    var selection: Set<URL> = []
    private(set) var loadError: String?
    /// Why the folder cannot be shown: Pane may not read it, or it is gone (a drive or share was disconnected).
    enum LoadProblem { case unreadable, unavailable, connectionLost, notConnected }
    private(set) var loadProblem: LoadProblem?
    /// True when a connection dropped and the list is the last one we had. It shows dimmed, with Reconnect.
    private(set) var isStale = false
    /// The open connections to servers. A remote folder is listed through one.
    var router = FileSystemRouter()
    /// Asked to open a file on a server. The app says what is not built yet.
    var requestRemoteOpen: ((URL) -> Void)?
    /// Called with a folder on this Mac after it was listed, so the tree shows what is in it now.
    var didList: ((URL) -> Void)?
    var isRemote: Bool { RemoteURL.isRemote(currentFolder) }
    private(set) var isLoading = false
    /// True once a load has taken more than half a second.
    private(set) var isSlow = false
    /// Runs once after the next listing that includes a change. File actions set it.
    var afterReload: (() -> Void)?
    /// After items are removed, select the one that moved up into the gap.
    var pendingSelection: (index: Int, removed: Set<URL>)?
    /// Called after every navigation, for what lives outside the tab: the tree,
    /// the Address bar, and the saved folder.
    var didNavigate: (() -> Void)?

    let view: ViewSettings
    /// What is typed in the Search box. Setting it does not search: call `search(_:)`.
    var searchText = ""
    /// True while the list shows search results instead of the folder.
    private(set) var isSearching = false
    /// True until the search has looked everywhere.
    private(set) var isSearchRunning = false
    /// Spotlight, when the app has it. Tests leave it nil, so they scan.
    var spotlight: SpotlightSearching?
    private var searchTask: Task<Void, Never>?
    /// Asked to open a file that is in the cloud but not on this Mac. The app downloads it, then opens it.
    var requestDownload: ((URL) -> Void)?
    /// Says whether a folder is on a network share. Tests swap it.
    var isNetworkFolder: (URL) -> Bool = { VolumeInfo.isNetwork($0) }
    /// Seconds between looks at the folder when it is on a share, or nil when the system tells us.
    private(set) var pollInterval: TimeInterval?
    private var pollTask: Task<Void, Never>?
    private let watcher = FolderWatcher()
    /// Whether the last listing included hidden items.
    private var listedHidden = false
    private var generation = 0
    private var reloadTask: Task<Void, Never>?

    var currentFolder: URL { history.current }
    var currentName: String { Locations.displayName(for: currentFolder) }
    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }
    var canGoUp: Bool { Breadcrumbs.parent(of: currentFolder) != nil }
    var selectedItems: [FolderItem] { items.filter { selection.contains($0.url) } }

    init(start: URL, view: ViewSettings) {
        self.view = view
        history = NavigationHistory(start: Self.canonical(start))
    }

    /// Lists the first folder. Call once, after `didNavigate` is set.
    func begin() {
        afterNavigation()
    }

    // MARK: Navigating

    /// One spelling per folder, so the same folder reached two ways is equal.
    static func canonical(_ url: URL) -> URL {
        if RemoteURL.isRemote(url) { return RemoteURL.canonical(url) }
        return URL(fileURLWithPath: url.standardizedFileURL.path)
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
        for item in chosen where !item.isFolder {
            if RemoteURL.isRemote(item.url) { requestRemoteOpen?(item.url); continue }
            if item.isOnlineOnly, let requestDownload { requestDownload(item.url) } else { openFile(item.url) }
        }
    }

    /// Moves the selection to the next or previous item, and keeps it inside the list.
    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { selection.contains($0.url) } ?? (delta > 0 ? -1 : items.count)
        selection = [items[min(max(current + delta, 0), items.count - 1)].url]
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
        endSearch(reload: false)
        selection = []
        didNavigate?()
        // A server does not report changes, so there is nothing to watch or poll. F5 looks again.
        if isRemote { watcher.stop() } else { watcher.watch(currentFolder) { [weak self] in self?.scheduleReload() } }
        startPolling()
        reload()
    }

    // MARK: Listing

    // MARK: Search

    /// Looks for the text in this folder and everything below it. Results stream in, in the
    /// chosen order. Empty text ends the search and shows the folder again.
    func search(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { endSearch(); return }
        isSearching = true
        isSearchRunning = true
        items = []
        selection = []
        loadError = nil
        let folder = currentFolder, hidden = view.showHidden, spotlight = spotlight
        searchTask = Task {
            // Wait for a pause in typing, so each letter does not start a new search.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            var found: [FolderItem] = []
            for await batch in FileSearch.results(for: trimmed, in: folder, spotlight: spotlight, showHidden: hidden) {
                if Task.isCancelled { return }
                found += batch
                items = sorted(found)
            }
            if !Task.isCancelled { isSearchRunning = false }
        }
    }

    /// Escape, or an empty Search box: back to the folder.
    func endSearch(reload shouldReload: Bool = true) {
        guard isSearching || !searchText.isEmpty else { return }
        searchTask?.cancel()
        let wasSearching = isSearching
        isSearching = false
        isSearchRunning = false
        searchText = ""
        if wasSearching, shouldReload { reload() }
    }

    func reload() {
        // A change in the folder does not replace search results.
        guard !isSearching else { return }
        let folder = currentFolder
        let hidden = view.showHidden
        listedHidden = hidden
        generation += 1
        let mine = generation
        isLoading = true
        isSlow = false
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            if mine == generation, isLoading { isSlow = true }
        }
        let router = self.router
        Task {
            let result: Result<[FolderItem], Error>
            if RemoteURL.isRemote(folder) {
                result = await Self.listRemote(folder, hidden: hidden, router: router)
            } else {
                result = await Task.detached { Result { try FolderLister.list(folder, showHidden: hidden) } }.value
            }
            guard mine == generation else { return }
            isLoading = false
            isSlow = false
            // A search that began while this listing was loading keeps its results.
            guard !isSearching else { return }
            switch result {
            case .success(let listed):
                items = sorted(listed)
                if !RemoteURL.isRemote(folder) { didList?(folder) }
                loadError = nil
                loadProblem = nil
                isStale = false
                let still = Set(listed.map(\.url))
                selection = selection.intersection(still)
                // After Trash or delete, select the item that moved up. Wait for a listing
                // where the removed items are gone: the folder watcher can reload early.
                if let pending = pendingSelection, !listed.isEmpty,
                   !listed.contains(where: { pending.removed.contains($0.url) }) {
                    pendingSelection = nil
                    // The Table drops its selection while it swaps rows, so choose after it settles.
                    let next = listed[min(pending.index, listed.count - 1)].url
                    Task {
                        try? await Task.sleep(for: .milliseconds(80))
                        if currentFolder == folder { selection = [next] }
                    }
                }
                if let action = afterReload {
                    afterReload = nil
                    // The Table drops its selection while it swaps rows, so act after it settles.
                    Task {
                        try? await Task.sleep(for: .milliseconds(80))
                        if currentFolder == folder { action() }
                    }
                }
            case .failure(let error):
                if let remote = error as? RemoteError, RemoteURL.isRemote(folder) {
                    switch remote {
                    case .connectionLost:
                        // Keep the last list, dimmed, so the person still sees where they were.
                        loadProblem = .connectionLost
                        loadError = "Connection lost."
                        isStale = true
                    case .notConnected:
                        items = []
                        loadProblem = .notConnected
                        loadError = "Not connected to this server."
                    case .denied, .other, .unknownHostKey, .hostKeyChanged:
                        items = []
                        loadProblem = .unreadable
                        loadError = remote.message
                    }
                } else {
                    items = []
                    // A folder that no longer exists, like one on a disconnected share, is not a permission problem.
                    loadProblem = FileManager.default.fileExists(atPath: folder.path) ? .unreadable : .unavailable
                    loadError = loadProblem == .unavailable ? "This folder is no longer available." : "Unable to read this folder."
                }
            }
        }
    }

    /// Lists a folder on a server, hiding dot-names unless asked, in the same order as a local folder.
    private static func listRemote(_ folder: URL, hidden: Bool, router: FileSystemRouter) async -> Result<[FolderItem], Error> {
        guard let remote = router.remote(for: folder) else { return .failure(RemoteError.notConnected) }
        do {
            let listed = try await remote.list(folder).filter { hidden || !$0.name.hasPrefix(".") }
            return .success(FolderLister.sorted(listed))
        } catch {
            return .failure(error)
        }
    }

    /// Stop waiting for a slow folder and go back to where we were (or home).
    func cancelLoad() {
        generation += 1
        isLoading = false
        isSlow = false
        if canGoBack { goBack() } else { go(to: Locations.home) }
    }

    /// Opens the connection again after it dropped, then lists the folder.
    func reconnect() {
        let folder = currentFolder
        let router = self.router
        Task {
            try? await router.remote(for: folder)?.reconnect()
            reload()
        }
    }

    /// A share does not report changes reliably, so look at it again every few seconds.
    private func startPolling() {
        pollTask?.cancel()
        pollInterval = isRemote ? nil : PollPolicy.interval(isLocal: !isNetworkFolder(currentFolder))
        guard let interval = pollInterval else { pollTask = nil; return }
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if !Task.isCancelled { reload() }
            }
        }
    }

    private func sorted(_ listed: [FolderItem]) -> [FolderItem] {
        FolderSorter.sorted(listed, key: view.sortKey, ascending: view.ascending, foldersFirst: view.foldersFirst)
    }

    /// After a view setting changed: list again when hidden items were turned on or off,
    /// otherwise just order the current listing again.
    func viewSettingsChanged() {
        if view.showHidden != listedHidden { reload() } else { items = sorted(items) }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .seconds(0.2))
            if !Task.isCancelled { reload() }
        }
    }
}
