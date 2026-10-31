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
        selection = []
        didNavigate?()
        watcher.watch(currentFolder) { [weak self] in self?.scheduleReload() }
        reload()
    }

    // MARK: Listing

    func reload() {
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
        Task {
            let result = await Task.detached { Result { try FolderLister.list(folder, showHidden: hidden) } }.value
            guard mine == generation else { return }
            isLoading = false
            isSlow = false
            switch result {
            case .success(let listed):
                items = sorted(listed)
                loadError = nil
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
            case .failure:
                items = []
                loadError = "Unable to read this folder."
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
