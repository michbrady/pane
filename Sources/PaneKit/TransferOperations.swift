import Foundation

/// Copy and move between this Mac and servers, in either direction (and server to server).
/// Local-to-local pastes stay with `FileOperations`. Here a folder is walked first, so the byte total is
/// known, then made folder by folder and file by file. Rules it keeps:
/// - A file shows under its name only when whole. A cancel or a failure removes what was half written.
/// - Cut removes the original only after the whole copy of it succeeded (this Mac's originals go to the Trash).
/// - There is no Undo for these: a server has no Trash to undo into.
public struct TransferOperations: Sendable {
    public typealias Progress = @Sendable (OperationProgress) -> Void

    private let router: FileSystemRouter

    public init(router: FileSystemRouter) {
        self.router = router
    }

    private enum Step: Sendable {
        case folder(URL)
        case file(from: URL, to: URL, size: Int64)
    }

    public func paste(_ sources: [URL], into folder: URL, mode: PasteMode,
                      resolve: FileOperations.Resolver, progress: Progress? = nil) async -> OperationResult {
        let verb = mode == .copy ? "Copy" : "Move"
        var result = OperationResult(record: OperationRecord(
            name: OperationRecord.title(verb, count: sources.count, firstName: sources.first.map { RemoteURL.name(of: $0) }), steps: []))
        guard let destination = router.filesystem(for: folder) else {
            result.failures = sources.map { OperationFailure(url: $0, message: RemoteError.notConnected.message) }
            return result
        }
        let destinationIsRemote = RemoteURL.isRemote(folder)
        var taken: [String: FolderItem] = [:]
        if destinationIsRemote {
            do { for item in try await destination.list(folder) { taken[item.name] = item } } catch {
                result.failures = sources.map { OperationFailure(url: $0, message: Self.words(error)) }
                return result
            }
        }
        func isTaken(_ name: String) -> Bool {
            destinationIsRemote ? taken[name] != nil : FileManager.default.fileExists(atPath: folder.appending(path: name).path)
        }

        var remembered: ConflictChoice?
        var doneBytes: Int64 = 0
        var totalBytes: Int64 = 0
        let meter = Meter(progress)

        for (index, source) in sources.enumerated() {
            if Task.isCancelled { result.wasCancelled = true; break }
            let name = RemoteURL.isRemote(source) ? RemoteURL.name(of: source) : source.lastPathComponent
            meter.report(OperationProgress(done: index, total: sources.count, current: name, bytesDone: doneBytes, bytesTotal: totalBytes), force: true)

            if Self.isInside(folder, of: source) {
                result.failures.append(OperationFailure(url: source, message: "A folder cannot go inside itself."))
                continue
            }
            let sameFolder = Self.parentKey(of: source) == Self.key(of: folder)
            if mode == .move && sameFolder { continue }

            var targetName = name
            var replacing = false
            if sameFolder {
                targetName = Self.unique(name, style: .copy, taken: isTaken)
            } else if isTaken(name) {
                let choice: ConflictChoice
                if let remembered {
                    choice = remembered
                } else {
                    let isFolder = await Self.isFolder(source, router: router)
                    let incoming = await Self.item(source, router: router)
                    let decision = await resolve(Conflict(source: source, existing: Self.child(folder, name), isFolder: isFolder,
                                                          incomingItem: incoming, existingItem: taken[name]))
                    choice = decision.choice
                    if decision.applyToAll { remembered = choice }
                }
                switch choice {
                case .cancel: result.wasCancelled = true
                case .skip: result.skipped.append(source)
                case .keepBoth: targetName = Self.unique(name, style: .keepBoth, taken: isTaken)
                case .replace: replacing = true
                }
                if result.wasCancelled { break }
                if choice == .skip { continue }
            }

            let target = Self.child(folder, targetName)
            do {
                let steps = try await plan(source, to: target)
                let weight: Int64 = RemoteURL.isRemote(source) && destinationIsRemote ? 2 : 1
                totalBytes += weight * steps.reduce(0) { sum, step in if case .file(_, _, let size) = step { sum + size } else { sum } }
                // Replace swaps one file for another. A folder that is already there is merged into.
                let replacesFile = replacing && !Self.isFolderStep(steps)
                let total = totalBytes
                for step in steps {
                    try Task.checkCancellation()
                    switch step {
                    case .folder(let url):
                        if !(await exists(url)) { try await router.filesystem(for: url)?.makeFolder(url) }
                    case .file(let from, let to, let size):
                        let before = doneBytes
                        try await copyFile(from, to: to, replacing: replacesFile, size: size) { sofar in
                            meter.report(OperationProgress(done: index, total: sources.count, current: name,
                                                           bytesDone: before + sofar, bytesTotal: total))
                        }
                        doneBytes = before + size * weight
                    }
                }
                if destinationIsRemote {
                    taken[targetName] = FolderItem(url: target, name: targetName, isFolder: Self.isFolderStep(steps), size: nil, modified: Date(), kind: "")
                }
                if mode == .move { try await removeOriginal(source) }
            } catch is CancellationError {
                result.wasCancelled = true
                break
            } catch {
                if Task.isCancelled { result.wasCancelled = true; break }
                result.failures.append(OperationFailure(url: source, message: Self.words(error)))
            }
        }
        meter.report(OperationProgress(done: sources.count, total: sources.count, current: "", bytesDone: doneBytes, bytesTotal: totalBytes), force: true)
        return result
    }

    // MARK: Planning

    /// Every folder to make and file to copy for one source, in order. A file is one step.
    private func plan(_ source: URL, to target: URL) async throws -> [Step] {
        if await isFolder(source) {
            var steps: [Step] = [.folder(target)]
            for child in try await children(of: source) {
                let name = RemoteURL.isRemote(child.url) ? RemoteURL.name(of: child.url) : child.url.lastPathComponent
                steps += try await plan(child.url, to: Self.child(target, name))
            }
            return steps
        }
        let size = (await Self.item(source, router: router)?.size) ?? 0
        return [.file(from: source, to: target, size: size)]
    }

    private func children(of folder: URL) async throws -> [FolderItem] {
        if RemoteURL.isRemote(folder) {
            guard let remote = router.remote(for: folder) else { throw RemoteError.notConnected }
            return try await remote.list(folder)
        }
        // Hidden files are part of a folder, so they are copied too.
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [])
        return urls.compactMap { FolderLister.item(at: $0) }
    }

    private func isFolder(_ url: URL) async -> Bool { await Self.isFolder(url, router: router) }
    private func exists(_ url: URL) async -> Bool { await router.filesystem(for: url)?.exists(url) ?? false }

    // MARK: Copying one file

    private func copyFile(_ from: URL, to: URL, replacing: Bool, size: Int64, progress: @escaping ByteProgress) async throws {
        let fromRemote = router.remote(for: from)
        let toRemote = router.remote(for: to)
        if RemoteURL.isRemote(from) && fromRemote == nil { throw RemoteError.notConnected }
        if RemoteURL.isRemote(to) && toRemote == nil { throw RemoteError.notConnected }

        switch (fromRemote, toRemote) {
        case (nil, let up?):
            try await up.upload(from, to: to, replacing: replacing, progress: progress)
        case (let down?, nil):
            let part = to.deletingLastPathComponent().appending(path: ".\(to.lastPathComponent).pane-part-\(UUID().uuidString)")
            do {
                try await down.download(from, to: part, progress: progress)
                try Self.place(part, at: to, replacing: replacing)
            } catch {
                try? FileManager.default.removeItem(at: part)
                throw error
            }
        case (let down?, let up?):
            // Server to server goes through a temporary file on this Mac.
            let temp = FileManager.default.temporaryDirectory.appending(path: "pane-transfer-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: temp) }
            try await down.download(from, to: temp, progress: progress)
            try await up.upload(temp, to: to, replacing: replacing) { progress(size + $0) }
        case (nil, nil):
            throw RemoteError.other("Both places are on this Mac.")
        }
    }

    /// Puts a finished download in place. An old file goes to the Trash first, and comes back if this fails.
    private static func place(_ part: URL, at target: URL, replacing: Bool) throws {
        let fm = FileManager.default
        var trashed: NSURL?
        if replacing, fm.fileExists(atPath: target.path) { try fm.trashItem(at: target, resultingItemURL: &trashed) }
        do { try fm.moveItem(at: part, to: target) } catch {
            if let trashed { try? fm.moveItem(at: trashed as URL, to: target) }
            throw error
        }
    }

    private func removeOriginal(_ source: URL) async throws {
        if let remote = router.remote(for: source) {
            try await remote.remove(source)
        } else {
            _ = try await router.local.trash(source)
        }
    }

    // MARK: Small helpers

    private static func words(_ error: Error) -> String {
        (error as? RemoteError)?.message ?? error.localizedDescription
    }

    private static func isFolderStep(_ steps: [Step]) -> Bool {
        if case .folder = steps.first { return true }
        return false
    }

    static func key(of url: URL) -> String {
        RemoteURL.isRemote(url) ? RemoteURL.canonical(url).absoluteString : url.standardizedFileURL.path
    }

    static func parentKey(of url: URL) -> String {
        if RemoteURL.isRemote(url) { return RemoteURL.parent(of: url).map { RemoteURL.canonical($0).absoluteString } ?? "" }
        return url.deletingLastPathComponent().standardizedFileURL.path
    }

    static func child(_ folder: URL, _ name: String) -> URL {
        RemoteURL.isRemote(folder) ? RemoteURL.child(of: folder, named: name) : folder.appending(path: name)
    }

    /// True when `folder` is `source` or inside it, on the same place.
    static func isInside(_ folder: URL, of source: URL) -> Bool {
        guard RemoteURL.isRemote(folder) == RemoteURL.isRemote(source) else { return false }
        if RemoteURL.isRemote(folder) {
            guard RemoteURL.serverKey(folder) == RemoteURL.serverKey(source) else { return false }
            let f = RemoteURL.canonical(folder).path, s = RemoteURL.canonical(source).path
            return f == s || f.hasPrefix(s + "/")
        }
        return FileOperations.isInside(folder, of: source)
    }

    static func item(_ url: URL, router: FileSystemRouter) async -> FolderItem? {
        if RemoteURL.isRemote(url) {
            guard let parent = RemoteURL.parent(of: url), let remote = router.remote(for: url) else { return nil }
            let name = RemoteURL.name(of: url)
            return (try? await remote.list(parent))?.first { $0.name == name }
        }
        return FolderLister.item(at: url)
    }

    static func isFolder(_ url: URL, router: FileSystemRouter) async -> Bool {
        await item(url, router: router)?.isFolder ?? false
    }

    static func unique(_ name: String, style: NameMaker.Style, taken: (String) -> Bool) -> String {
        guard taken(name) else { return name }
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var n = 1
        while true {
            let stem: String
            switch style {
            case .copy: stem = n == 1 ? "\(base) - Copy" : "\(base) - Copy (\(n))"
            case .keepBoth: stem = "\(base) (\(n + 1))"
            }
            let candidate = ext.isEmpty ? stem : "\(stem).\(ext)"
            if !taken(candidate) { return candidate }
            n += 1
        }
    }

    /// Passes progress on at most ten times a second, so a fast transfer does not flood the window.
    private final class Meter: @unchecked Sendable {
        private let sink: Progress?
        private let lock = NSLock()
        private var last = ContinuousClock.now
        init(_ sink: Progress?) { self.sink = sink }

        func report(_ value: OperationProgress, force: Bool = false) {
            guard let sink else { return }
            let now = ContinuousClock.now
            let send = lock.withLock { () -> Bool in
                guard force || now - last >= .milliseconds(100) else { return false }
                last = now
                return true
            }
            if send { sink(value) }
        }
    }
}
