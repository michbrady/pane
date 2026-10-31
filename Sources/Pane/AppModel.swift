import AppKit
import Foundation
import Observation
import PaneKit

/// A record that Redo can update: a re-trashed item lands in a new place in the Trash.
final class RecordBox: @unchecked Sendable {
    var record: OperationRecord
    init(_ record: OperationRecord) { self.record = record }
}

/// A pasted item whose name is already taken. `continuation` resumes the paste.
struct PendingConflict {
    let conflict: Conflict
    let incoming: FolderItem?
    let existing: FolderItem?
    let continuation: CheckedContinuation<ConflictDecision, Never>?
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let tab: FolderTab

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
    // File operations
    private(set) var clipboard = Clipboard()
    private let operations = FileOperations(LocalFileSystem(
        trashFolder: Locations.isOverridden ? Locations.home.appending(path: ".Trash", directoryHint: .isDirectory) : nil))
    /// The running copy or move. A sheet shows it once it takes more than a second.
    private(set) var progress: OperationProgress?
    private(set) var progressTitle = ""
    private(set) var progressVisible = false
    private var operationTask: Task<Void, Never>?
    /// A name conflict waiting for the person's choice.
    private(set) var pendingConflict: PendingConflict?
    /// Items waiting for the person to confirm Delete Immediately.
    var pendingDelete: [URL]?
    /// After Trash, select the item that moved up into the gap.
    private var pendingSelection: (index: Int, removed: Set<URL>)?
    // Rename
    private(set) var renamingURL: URL?
    var renameText = ""
    private(set) var renameError: String?
    /// Runs once after the next listing that includes the change.
    private var afterReload: (() -> Void)?
    /// A message for an alert, after something failed.
    var alertMessage: String?

    /// The window's undo manager, set by ContentView. The Edit menu uses it.
    var windowUndoManager: UndoManager?
    private let fallbackUndoManager = UndoManager()
    var undoManager: UndoManager { windowUndoManager ?? fallbackUndoManager }

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
        tab.begin()
    }

    // MARK: Copy, cut, paste

    private var editingText: NSText? { NSApp.keyWindow?.firstResponder as? NSText }
    var canCopy: Bool { !tab.selection.isEmpty || isEditingAddress }

    func isCut(_ url: URL) -> Bool { clipboard.isCut(url) }

    func copySelection() {
        if let text = editingText { text.copy(nil); return }
        guard !tab.selection.isEmpty else { return }
        clipboard.write(Array(tab.selection), cut: false)
    }

    func cutSelection() {
        if let text = editingText { text.cut(nil); return }
        guard !tab.selection.isEmpty else { return }
        clipboard.write(Array(tab.selection), cut: true)
    }

    func clearCut() {
        clipboard.clearCut()
    }

    func paste() {
        if let text = editingText { text.paste(nil); return }
        let sources = clipboard.urls
        guard !sources.isEmpty, operationTask == nil else { return }
        startPaste(sources, into: tab.currentFolder, mode: clipboard.isCutActive ? .move : .copy, clearsCut: clipboard.isCutActive)
    }

    private func startPaste(_ sources: [URL], into folder: URL, mode: PasteMode, clearsCut: Bool) {
        guard !sources.isEmpty, operationTask == nil else { return }
        run(title: mode == .copy ? "Copying" : "Moving") { [self] in
            await operations.paste(sources, into: folder, mode: mode,
                                   resolve: { [self] conflict in await askConflict(conflict) },
                                   progress: { p in Task { @MainActor in self.progress = p } })
        } finished: { [self] result in
            if clearsCut { clipboard.clearCut() }
            return result
        }
    }

    // MARK: Drag and drop

    /// The tab.items being dragged out of this window, so a hover can tell move from copy.
    private(set) var dragSources: [URL] = []

    func dragStarted(_ urls: [URL]) {
        dragSources = urls
    }

    /// Move or copy, from the volumes and the Option and Command keys held right now.
    func dropMode(into folder: URL) -> PasteMode {
        let keys = NSEvent.modifierFlags
        // A drag from another app has unknown sources until it lands, so it copies.
        let same = !dragSources.isEmpty && DropRules.sameVolume(dragSources, as: folder)
        return DropRules.mode(sameVolume: same, option: keys.contains(.option), command: keys.contains(.command))
    }

    func drop(_ urls: [URL], into folder: URL) {
        let mode = DropRules.mode(
            sameVolume: DropRules.sameVolume(urls, as: folder),
            option: NSEvent.modifierFlags.contains(.option), command: NSEvent.modifierFlags.contains(.command))
        dragSources = []
        startPaste(urls, into: folder, mode: mode, clearsCut: false)
    }

    /// For tests: a drop with the keys held chosen by the caller.
    func drop(_ urls: [URL], into folder: URL, option: Bool, command: Bool) {
        let mode = DropRules.mode(sameVolume: DropRules.sameVolume(urls, as: folder), option: option, command: command)
        startPaste(urls, into: folder, mode: mode, clearsCut: false)
    }

    /// Runs an operation in the background. The progress sheet shows after one second.
    private func run(title: String, _ work: @escaping () async -> OperationResult,
                     finished: @escaping (OperationResult) -> OperationResult) {
        progressTitle = title
        progress = nil
        progressVisible = false
        operationTask = Task {
            let reveal = Task {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { progressVisible = true }
            }
            let result = finished(await work())
            reveal.cancel()
            progressVisible = false
            progress = nil
            operationTask = nil
            report(result)
            remember(result.record)
            tab.reload()
        }
    }

    private func askConflict(_ conflict: Conflict) async -> ConflictDecision {
        await withCheckedContinuation { continuation in
            pendingConflict = PendingConflict(
                conflict: conflict,
                incoming: FolderLister.item(at: conflict.source),
                existing: FolderLister.item(at: conflict.existing),
                continuation: continuation)
        }
    }

    func resolveConflict(_ choice: ConflictChoice, applyToAll: Bool) {
        guard let pending = pendingConflict else { return }
        pendingConflict = nil
        pending.continuation?.resume(returning: ConflictDecision(choice: choice, applyToAll: applyToAll))
    }

    func showConflictForSnapshot(incoming: URL, existing: URL) {
        pendingConflict = PendingConflict(
            conflict: Conflict(source: incoming, existing: existing, isFolder: false),
            incoming: FolderLister.item(at: incoming), existing: FolderLister.item(at: existing), continuation: nil)
    }

    func hideConflictForSnapshot() {
        pendingConflict = nil
    }

    // MARK: Trash and delete

    func trashSelection() {
        let urls = Array(tab.selection)
        guard !urls.isEmpty, operationTask == nil, editingText == nil else { return }
        tab.pendingSelection = tab.items.firstIndex { tab.selection.contains($0.url) }.map { ($0, Set(urls)) }
        run(title: "Moving to Trash") { [self] in await operations.trash(urls) } finished: { $0 }
    }

    /// Shift-Delete asks first, because this cannot be undone.
    func askDeleteImmediately() {
        guard !tab.selection.isEmpty, editingText == nil else { return }
        pendingDelete = Array(tab.selection)
    }

    func deleteImmediately() {
        guard let urls = pendingDelete, operationTask == nil else { return }
        pendingDelete = nil
        tab.pendingSelection = tab.items.firstIndex { urls.contains($0.url) }.map { ($0, Set(urls)) }
        run(title: "Deleting") { [self] in
            OperationResult(record: OperationRecord(name: "Delete Immediately", steps: []),
                            failures: await operations.deleteImmediately(urls))
        } finished: { $0 }
    }

    /// For snapshots: shows the progress sheet without a long copy.
    func showProgressForSnapshot() {
        progressTitle = "Copying"
        progress = OperationProgress(done: 3, total: 12, current: "Quarterly review.docx")
        progressVisible = true
    }

    func hideProgressForSnapshot() {
        progressVisible = false
        progress = nil
    }

    // MARK: Rename and new folder

    var canRename: Bool { tab.selection.count == 1 && editingText == nil }

    func beginRename() {
        guard canRename, let item = tab.selectedItems.first else { return }
        renameText = item.name
        renameError = nil
        renamingURL = item.url
    }

    func cancelRename() {
        renamingURL = nil
        renameError = nil
    }

    /// Return commits. Clicking away commits too, but never shows an error: it just stops.
    func commitRename(fromBlur: Bool = false) {
        guard let url = renamingURL, let item = tab.items.first(where: { $0.url == url }) else { return }
        if renameText == item.name { cancelRename(); return }
        let text = renameText
        Task {
            do {
                let record = try await operations.rename(url, to: text)
                renamingURL = nil
                renameError = nil
                remember(record)
                let renamed = url.deletingLastPathComponent().appending(path: text.trimmingCharacters(in: .whitespacesAndNewlines))
                selectAfterReload(path: renamed.standardizedFileURL.path)
                tab.reload()
            } catch let error as FileOperations.RenameError {
                if fromBlur { cancelRename(); return }
                switch error {
                case .empty: renameError = "Give the item a name."
                case .hasSlash: renameError = "A name cannot contain / or :."
                case .taken: renameError = "An item with this name already exists."
                }
            } catch {
                renameError = error.localizedDescription
            }
        }
    }

    /// Cmd-Shift-N: make "New folder" and start naming it.
    func newFolder() {
        guard editingText == nil, operationTask == nil else { return }
        let folder = tab.currentFolder
        Task {
            do {
                let (url, record) = try await operations.makeFolder(in: folder)
                remember(record)
                tab.afterReload = { [self] in
                    guard let item = tab.items.first(where: { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }) else { return }
                    tab.selection = [item.url]
                    beginRename()
                }
                tab.reload()
            } catch {
                alertMessage = "Unable to make a folder here. \(error.localizedDescription)"
            }
        }
    }

    private func selectAfterReload(path: String) {
        tab.afterReload = { [self] in
            if let item = tab.items.first(where: { $0.url.standardizedFileURL.path == path }) { tab.selection = [item.url] }
        }
    }

    // MARK: Undo

    /// Keeps a finished change so Edit > Undo can reverse it, and Redo can do it again.
    private func remember(_ record: OperationRecord) {
        guard !record.isEmpty else { return }
        registerUndo(RecordBox(record))
    }

    private func registerUndo(_ box: RecordBox) {
        // Each change is its own Undo step. Without this, changes made in the same
        // run loop pass share one group, and one Undo would reverse all of them.
        if undoManager.groupingLevel > 0 { undoManager.endUndoGrouping() }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { model in model.performUndo(box) }
        undoManager.setActionName(box.record.name)
        undoManager.endUndoGrouping()
    }

    private func performUndo(_ box: RecordBox) {
        // Registered while undoing, so it becomes the Redo.
        undoManager.registerUndo(withTarget: self) { model in model.performRedo(box) }
        undoManager.setActionName(box.record.name)
        Task {
            do { try await operations.undo(box.record) } catch { alertMessage = "Unable to undo. \(error.localizedDescription)" }
            tab.reload()
        }
    }

    private func performRedo(_ box: RecordBox) {
        undoManager.registerUndo(withTarget: self) { model in model.performUndo(box) }
        undoManager.setActionName(box.record.name)
        Task {
            do { box.record = try await operations.redo(box.record) } catch { alertMessage = "Unable to redo. \(error.localizedDescription)" }
            tab.reload()
        }
    }

    func cancelOperation() {
        operationTask?.cancel()
    }

    private func report(_ result: OperationResult) {
        if let first = result.failures.first {
            let more = result.failures.count > 1 ? " \(result.failures.count - 1) more failed." : ""
            alertMessage = "Unable to complete \(first.url.lastPathComponent). \(first.message)\(more)"
        }
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