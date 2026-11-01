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

/// Copy, cut, paste, drag, Trash, rename, new folder, and Undo, for whichever tab is active.
/// It owns the file operations, the clipboard, and the sheets they show.
@Observable
final class FileActions {
    /// The tab these actions work on. AppModel sets it; with tabs it returns the active one.
    var tabProvider: () -> FolderTab = { fatalError("FileActions.tabProvider is not set") }
    private var tab: FolderTab { tabProvider() }

    // File operations
    private(set) var clipboard = Clipboard()
    private let operations = FileOperations(LocalFileSystem(
        trashFolder: Locations.isOverridden ? Locations.home.appending(path: ".Trash", directoryHint: .isDirectory) : nil))
    /// The running copy or move. A sheet shows it once it takes more than a second.
    private(set) var progress: OperationProgress?
    private(set) var progressTitle = ""
    /// "12 MB of 40 MB · 3.2 MB/s · 9 seconds left", for a copy to or from a server.
    private(set) var progressDetail = ""
    private var stats = TransferStats()
    /// The servers that are connected. AppModel sets it, so a paste can reach them.
    var router = FileSystemRouter()
    private var transfers: TransferOperations { TransferOperations(router: router) }

    // Open and edit a file on a server (S-066)
    @ObservationIgnored private var editsStore: RemoteEdits?
    private var edits: RemoteEdits {
        if let editsStore { return editsStore }
        let made = RemoteEdits(router: router, root: FileManager.default.temporaryDirectory.appending(path: "Pane-remote-\(UUID().uuidString)", directoryHint: .isDirectory))
        editsStore = made
        return made
    }
    /// A short note for the Status bar, like "Uploaded Notes.txt". It clears itself.
    private(set) var statusMessage: String?
    /// A saved file whose server copy changed since it was opened, waiting for the person's choice.
    private(set) var pendingEditConflict: (id: UUID, name: String)?
    private var isSyncingEdits = false
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    private(set) var progressVisible = false
    private var operationTask: Task<Void, Never>?
    /// Rename, New Folder, Undo, and Redo run in the background without `operationTask`.
    private var backgroundWork = 0
    /// True while a file operation or a background change is still running.
    var isBusy: Bool { operationTask != nil || backgroundWork > 0 }
    /// A name conflict waiting for the person's choice.
    private(set) var pendingConflict: PendingConflict?
    /// Items waiting for the person to confirm Delete Immediately.
    var pendingDelete: [URL]?
    // Rename
    private(set) var renamingURL: URL?
    var renameText = ""
    private(set) var renameError: String?
    /// A message for an alert, after something failed.
    var alertMessage: String?

    /// The window's undo manager, set by ContentView. The Edit menu uses it.
    var windowUndoManager: UndoManager?
    private let fallbackUndoManager = UndoManager()
    var undoManager: UndoManager { windowUndoManager ?? fallbackUndoManager }

    // MARK: Copy, cut, paste

    /// Changing files on a server (paste, Trash, rename, new folder, delete, drop) is not built yet.
    /// The operations for the current tab: this Mac's, or the server's. A server address never reaches a local
    /// file call. Nil, with a message, when the tab's server is no longer connected.
    private func operationsForTab() -> FileOperations? {
        guard tab.isRemote else { return operations }
        guard let server = router.remote(for: tab.currentFolder) else {
            alertMessage = RemoteError.notConnected.message
            return nil
        }
        return FileOperations(server)
    }

    private var editingText: NSText? { NSApp.keyWindow?.firstResponder as? NSText }

    /// True when the pasteboard holds files to paste.
    var canPaste: Bool { !clipboard.urls.isEmpty }

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
        // A server address must never reach the local file calls. Anything that touches a server goes the other way.
        if sources.contains(where: RemoteURL.isRemote) || RemoteURL.isRemote(folder) {
            run(title: mode == .copy ? "Copying" : "Moving") { [self] in
                await transfers.paste(sources, into: folder, mode: mode,
                                      resolve: { [self] conflict in await askConflict(conflict) },
                                      progress: { p in Task { @MainActor in self.noteProgress(p) } })
            } finished: { [self] result in
                if clearsCut { clipboard.clearCut() }
                return result
            }
            return
        }
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
        // A drag from this window starts from the selected rows.
        let sources = dragSources.isEmpty ? Array(tab.selection) : dragSources
        let same = !sources.isEmpty && DropRules.sameVolume(sources, as: folder)
        return DropRules.mode(sameVolume: same, option: keys.contains(.option), command: keys.contains(.command))
    }

    /// Move or copy, with the keys that were held at the moment of the drop.
    func drop(_ urls: [URL], into folder: URL, option: Bool, command: Bool) {
        dragSources = []
        let mode = DropRules.mode(sameVolume: DropRules.sameVolume(urls, as: folder), option: option, command: command)
        startPaste(urls, into: folder, mode: mode, clearsCut: false)
    }

    /// Runs an operation in the background. The progress sheet shows after one second.
    private func run(title: String, _ work: @escaping () async -> OperationResult,
                     finished: @escaping (OperationResult) -> OperationResult) {
        progressTitle = title
        progress = nil
        progressDetail = ""
        stats = TransferStats()
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
                incoming: conflict.incomingItem ?? FolderLister.item(at: conflict.source),
                existing: conflict.existingItem ?? FolderLister.item(at: conflict.existing),
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

    // MARK: Cloud files

    /// A file that is in the cloud and not here: download it, with the progress sheet after a second, then open it.
    /// `open` is a parameter so tests do not launch an app.
    func downloadAndOpen(_ url: URL, open: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        guard operationTask == nil else { return }
        run(title: "Downloading") {
            var result = OperationResult(record: OperationRecord(name: "Download", steps: []))
            do { try await CloudDownload.materialize(url) } catch {
                result.failures.append(OperationFailure(url: url, message: "It could not be downloaded. \(error.localizedDescription)"))
            }
            return result
        } finished: { result in
            if result.failures.isEmpty { open(url) }
            return result
        }
    }

    // MARK: Open and edit a file on a server

    /// Downloads the file to a temporary folder, with the progress sheet after a second, then opens it.
    /// Saves made in that app go back to the server. `open` is a parameter so tests do not launch an app.
    func openRemoteFile(_ url: URL, open: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        guard operationTask == nil else { return }
        let name = RemoteURL.name(of: url)
        let size = tab.items.first { $0.url == url }?.size ?? 0
        var copy: URL?
        run(title: "Downloading") { [self] in
            var result = OperationResult(record: OperationRecord(name: "Open", steps: []))
            do {
                copy = try await edits.open(url, progress: { bytes in
                    Task { @MainActor in self.noteProgress(OperationProgress(done: 0, total: 1, current: name, bytesDone: bytes, bytesTotal: size)) }
                })
            } catch is CancellationError {
                result.wasCancelled = true
            } catch {
                result.failures.append(OperationFailure(url: url, message: error.localizedDescription))
            }
            return result
        } finished: { [self] result in
            if let copy, result.failures.isEmpty {
                if !open(copy) { alertMessage = "No app can open \(name)." }
                startSyncingEdits()
            }
            return result
        }
    }

    /// Looks at the opened copies a couple of times a second. Tests call `syncRemoteEdits()` instead.
    private func startSyncingEdits() {
        guard syncTask == nil, !Locations.isOverridden else { return }
        syncTask = Task { [self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1500))
                await syncRemoteEdits()
            }
        }
    }

    /// Sends back every copy that was saved. A file that changed on the server in the meantime asks first.
    func syncRemoteEdits() async {
        guard !isSyncingEdits, pendingEditConflict == nil else { return }
        isSyncingEdits = true
        defer { isSyncingEdits = false }
        for session in edits.changed() {
            do {
                switch try await edits.sync(session.id) {
                case .uploaded: say("Uploaded \(session.name)")
                case .serverChanged:
                    pendingEditConflict = (session.id, session.name)
                    return
                case .unchanged: break
                }
            } catch {
                // Say so once. The next save tries again.
                edits.hold(session.id)
                alertMessage = "Unable to upload \(session.name). \(error.localizedDescription)"
            }
        }
    }

    /// Replace sends the person's version over the server's. Not Now leaves both, and asks again after the next save.
    func resolveEditConflict(replace: Bool) {
        guard let pending = pendingEditConflict else { return }
        pendingEditConflict = nil
        guard replace else { edits.hold(pending.id); return }
        backgroundWork += 1
        Task {
            defer { backgroundWork -= 1 }
            do {
                if try await edits.sync(pending.id, replacing: true) == .uploaded { say("Uploaded \(pending.name)") }
            } catch {
                edits.hold(pending.id)
                alertMessage = "Unable to upload \(pending.name). \(error.localizedDescription)"
            }
        }
    }

    /// For snapshots: the question a changed server file asks.
    func showEditConflictForSnapshot(name: String) { pendingEditConflict = (UUID(), name) }
    func hideEditConflictForSnapshot() { pendingEditConflict = nil; statusMessage = nil }
    func showStatusForSnapshot(_ text: String) { statusMessage = text }

    /// When Pane quits: send what was saved, and delete the temporary copies. False if the person chose to stay.
    func finishRemoteEdits() async -> Bool {
        guard editsStore != nil, !edits.isEmpty else { return true }
        syncTask?.cancel()
        await syncRemoteEdits()
        let unsent = edits.changed()
        if !unsent.isEmpty {
            let alert = NSAlert()
            alert.messageText = unsent.count == 1 ? "\u{201C}\(unsent[0].name)\u{201D} has changes that are not on the server." : "\(unsent.count) files have changes that are not on the server."
            alert.informativeText = "If you quit now, those changes are lost."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Quit Anyway")
            if alert.runModal() == .alertFirstButtonReturn { return false }
        }
        edits.discardAll()
        return true
    }

    /// Removes the temporary copies at once. For tests.
    func discardRemoteEditsForTest() { edits.discardAll() }
    var remoteEditCopiesExist: Bool { editsStore.map { !$0.isEmpty } ?? false }

    private func say(_ text: String) {
        statusMessage = text
        Task {
            try? await Task.sleep(for: .seconds(5))
            if statusMessage == text { statusMessage = nil }
        }
    }

    // MARK: Trash and delete

    func trashSelection() {
        // A server has no Trash, so Delete asks first, like Shift-Delete does.
        if tab.isRemote { askDeleteImmediately(); return }
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

    /// True when the items waiting to be deleted are on a server, which has no Trash.
    var deletingOnServer: Bool { pendingDelete?.first.map(RemoteURL.isRemote) ?? false }

    /// The question, naming what goes and where from. "Delete 3 items from nas?"
    var deleteTitle: String {
        guard let urls = pendingDelete, let first = urls.first else { return "" }
        if RemoteURL.isRemote(first) {
            let server = first.host ?? "the server"
            return urls.count == 1 ? "Delete \u{201C}\(RemoteURL.name(of: first))\u{201D} from \(server)?" : "Delete \(urls.count) items from \(server)?"
        }
        return urls.count == 1 ? "Delete \u{201C}\(first.lastPathComponent)\u{201D} Immediately?" : "Delete \(urls.count) Items Immediately?"
    }

    var deleteButtonTitle: String { deletingOnServer ? "Delete" : "Delete Immediately" }

    func deleteImmediately() {
        guard let urls = pendingDelete, operationTask == nil else { return }
        pendingDelete = nil
        guard let ops = operationsForTab() else { return }
        tab.pendingSelection = tab.items.firstIndex { urls.contains($0.url) }.map { ($0, Set(urls)) }
        run(title: "Deleting") { [self] in
            OperationResult(record: OperationRecord(name: "Delete Immediately", steps: []),
                            failures: await ops.deleteImmediately(urls))
        } finished: { $0 }
    }

    /// For snapshots: shows the progress sheet without a long copy.
    func showProgressForSnapshot() {
        progressTitle = "Copying"
        progress = OperationProgress(done: 3, total: 12, current: "Quarterly review.docx")
        progressVisible = true
    }

    /// A copy to a server, part of the way: bytes, speed, and time left.
    func showTransferProgressForSnapshot() {
        progressTitle = "Copying"
        progress = OperationProgress(done: 0, total: 1, current: "Trip video.mov", bytesDone: 412_000_000, bytesTotal: 1_180_000_000)
        progressDetail = "412 MB of 1.2 GB · 8.4 MB/s · 2 minutes left"
        progressVisible = true
    }

    func hideProgressForSnapshot() {
        progressVisible = false
        progressDetail = ""
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
        guard let ops = operationsForTab() else { cancelRename(); return }
        let onServer = tab.isRemote
        let text = renameText
        backgroundWork += 1
        Task {
            defer { backgroundWork -= 1 }
            do {
                let record = try await ops.rename(url, to: text)
                renamingURL = nil
                renameError = nil
                if !onServer { remember(record) }   // a server has no Trash to undo into
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
        guard editingText == nil, operationTask == nil, let ops = operationsForTab() else { return }
        let onServer = tab.isRemote
        let folder = tab.currentFolder
        backgroundWork += 1
        Task {
            defer { backgroundWork -= 1 }
            do {
                let (url, record) = try await ops.makeFolder(in: folder)
                if !onServer { remember(record) }
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
        backgroundWork += 1
        Task {
            defer { backgroundWork -= 1 }
            do { try await operations.undo(box.record) } catch { alertMessage = "Unable to undo. \(error.localizedDescription)" }
            tab.reload()
        }
    }

    private func performRedo(_ box: RecordBox) {
        undoManager.registerUndo(withTarget: self) { model in model.performUndo(box) }
        undoManager.setActionName(box.record.name)
        backgroundWork += 1
        Task {
            defer { backgroundWork -= 1 }
            do { box.record = try await operations.redo(box.record) } catch { alertMessage = "Unable to redo. \(error.localizedDescription)" }
            tab.reload()
        }
    }

    private func noteProgress(_ p: OperationProgress) {
        progress = p
        guard p.bytesTotal > 0 else { return }
        stats.add(bytes: p.bytesDone, at: Date())
        progressDetail = stats.describe(done: p.bytesDone, total: p.bytesTotal)
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
}
