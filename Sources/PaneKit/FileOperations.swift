import Foundation

public enum PasteMode: Sendable { case copy, move }

/// A pasted item's name is already taken in the destination.
public struct Conflict: Sendable {
    public let source: URL
    public let existing: URL
    public let isFolder: Bool
}

public enum ConflictChoice: Sendable { case replace, skip, keepBoth, cancel }

public struct ConflictDecision: Sendable {
    public var choice: ConflictChoice
    /// Use the same choice for every conflict left in this batch.
    public var applyToAll: Bool

    public init(choice: ConflictChoice, applyToAll: Bool = false) {
        self.choice = choice
        self.applyToAll = applyToAll
    }
}

public struct OperationProgress: Sendable {
    public let done: Int
    public let total: Int
    public let current: String
}

public struct OperationFailure: Sendable {
    public let url: URL
    public let message: String
}

public struct OperationResult: Sendable {
    public var record: OperationRecord
    public var skipped: [URL] = []
    public var failures: [OperationFailure] = []
    public var wasCancelled = false
}

/// Copy, move, Trash, rename, and new folder, with conflicts and undo records.
/// It works on a `FileSystem`, so the same rules apply to every kind of place.
public struct FileOperations: Sendable {
    public typealias Resolver = @Sendable (Conflict) async -> ConflictDecision
    public typealias Progress = @Sendable (OperationProgress) -> Void

    private let fs: FileSystem

    public init(_ fs: FileSystem) {
        self.fs = fs
    }

    // MARK: Paste

    public func paste(_ sources: [URL], into folder: URL, mode: PasteMode,
                      resolve: Resolver, progress: Progress? = nil) async -> OperationResult {
        let verb = mode == .copy ? "Copy" : "Move"
        var result = OperationResult(record: OperationRecord(
            name: OperationRecord.title(verb, count: sources.count, firstName: sources.first?.lastPathComponent), steps: []))
        var remembered: ConflictChoice?

        for (index, source) in sources.enumerated() {
            if Task.isCancelled { result.wasCancelled = true; break }
            progress?(OperationProgress(done: index, total: sources.count, current: source.lastPathComponent))
            let name = source.lastPathComponent

            if Self.isInside(folder, of: source) {
                result.failures.append(OperationFailure(url: source, message: "A folder cannot go inside itself."))
                continue
            }
            let sameFolder = source.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path
            if mode == .move && sameFolder { continue }

            var target = folder.appending(path: name)
            var replacing = false
            if sameFolder {
                target = await NameMaker.unique(target, style: .copy, in: fs)
            } else if await fs.exists(target) {
                let choice: ConflictChoice
                if let remembered {
                    choice = remembered
                } else {
                    let isFolder = ((try? await fs.list(folder))?.first { $0.url.lastPathComponent == name }?.isFolder) ?? false
                    let decision = await resolve(Conflict(source: source, existing: target, isFolder: isFolder))
                    choice = decision.choice
                    if decision.applyToAll { remembered = choice }
                }
                switch choice {
                case .cancel: result.wasCancelled = true
                case .skip: result.skipped.append(source)
                case .keepBoth: target = await NameMaker.unique(target, style: .keepBoth, in: fs)
                case .replace: replacing = true
                }
                if result.wasCancelled { break }
                if choice == .skip { continue }
            }

            do {
                result.record.steps += try await place(source, at: target, mode: mode, replacing: replacing)
            } catch {
                result.failures.append(OperationFailure(url: source, message: error.localizedDescription))
            }
        }
        progress?(OperationProgress(done: sources.count, total: sources.count, current: ""))
        return result
    }

    /// Replacing never loses the original: the old item goes to the Trash first
    /// (or the copy is made beside it first), and is put back if the new one fails.
    private func place(_ source: URL, at target: URL, mode: PasteMode, replacing: Bool) async throws -> [OperationRecord.Step] {
        let step: OperationRecord.Step = mode == .copy ? .copy(source: source, destination: target) : .move(from: source, to: target)
        guard replacing else {
            try await perform(step)
            return [step]
        }
        var temp: URL?
        if mode == .copy {
            let hidden = target.deletingLastPathComponent().appending(path: ".\(target.lastPathComponent).pane-\(UUID().uuidString)")
            try await fs.copy(source, to: hidden)
            temp = hidden
        }
        let trashed = try await fs.trash(target)
        do {
            if let temp { try await fs.move(temp, to: target) } else { try await perform(step) }
        } catch {
            if let trashed { try? await fs.move(trashed, to: target) }
            if let temp { try? await fs.remove(temp) }
            throw error
        }
        return [.trash(original: target, trashed: trashed), step]
    }

    static func isInside(_ folder: URL, of source: URL) -> Bool {
        let f = folder.standardizedFileURL.path, s = source.standardizedFileURL.path
        return f == s || f.hasPrefix(s + "/")
    }

    // MARK: Trash, new folder, rename

    public func trash(_ urls: [URL]) async -> OperationResult {
        var result = OperationResult(record: OperationRecord(
            name: "Move to Trash", steps: []))
        for url in urls {
            do {
                let trashed = try await fs.trash(url)
                result.record.steps.append(.trash(original: url, trashed: trashed))
            } catch {
                result.failures.append(OperationFailure(url: url, message: error.localizedDescription))
            }
        }
        return result
    }

    /// For Delete Immediately. Not undoable, so it returns no record.
    public func deleteImmediately(_ urls: [URL]) async -> [OperationFailure] {
        var failures: [OperationFailure] = []
        for url in urls {
            do { try await fs.remove(url) } catch {
                failures.append(OperationFailure(url: url, message: error.localizedDescription))
            }
        }
        return failures
    }

    /// "New folder", then "New folder (2)".
    public func makeFolder(in parent: URL, name: String = "New folder") async throws -> (URL, OperationRecord) {
        let url = await NameMaker.unique(parent.appending(path: name), style: .keepBoth, in: fs)
        try await fs.makeFolder(url)
        return (url, OperationRecord(name: "New Folder", steps: [.makeFolder(url)]))
    }

    public enum RenameError: Error, Equatable, Sendable { case empty, hasSlash, taken }

    public func rename(_ url: URL, to newName: String) async throws -> OperationRecord {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw RenameError.empty }
        guard !name.contains("/"), !name.contains(":") else { throw RenameError.hasSlash }
        let target = url.deletingLastPathComponent().appending(path: name)
        guard target.path != url.path else { return OperationRecord(name: "Rename", steps: []) }
        guard !(await fs.exists(target)) else { throw RenameError.taken }
        try await fs.move(url, to: target)
        return OperationRecord(name: "Rename", steps: [.rename(from: url, to: target)])
    }

    // MARK: Undo and redo

    private func perform(_ step: OperationRecord.Step) async throws {
        switch step {
        case .copy(let source, let destination): try await fs.copy(source, to: destination)
        case .move(let from, let to), .rename(let from, let to): try await fs.move(from, to: to)
        case .trash(let original, _): _ = try await fs.trash(original)
        case .makeFolder(let url): try await fs.makeFolder(url)
        }
    }

    /// Reverses a record, last step first. A copy or new folder goes to the Trash, so Redo can bring it back.
    public func undo(_ record: OperationRecord) async throws {
        for step in record.steps.reversed() {
            switch step {
            case .copy(_, let destination): _ = try await fs.trash(destination)
            case .move(let from, let to), .rename(let from, let to): try await fs.move(to, to: from)
            case .trash(let original, let trashed): if let trashed { try await fs.move(trashed, to: original) }
            case .makeFolder(let url): _ = try await fs.trash(url)
            }
        }
    }

    /// Does a record again. Trash steps learn their new place in the Trash.
    public func redo(_ record: OperationRecord) async throws -> OperationRecord {
        var record = record
        for (index, step) in record.steps.enumerated() {
            if case .trash(let original, _) = step {
                record.steps[index] = .trash(original: original, trashed: try await fs.trash(original))
            } else {
                try await perform(step)
            }
        }
        return record
    }
}

/// Names for copies and new items.
public enum NameMaker {
    public enum Style: Sendable {
        /// "report - Copy.txt", "report - Copy (2).txt" (what Explorer does).
        case copy
        /// "report (2).txt".
        case keepBoth
    }

    public static func unique(_ url: URL, style: Style, in fs: FileSystem) async -> URL {
        guard await fs.exists(url) else { return url }
        let ext = url.pathExtension
        let base = ext.isEmpty ? url.lastPathComponent : String(url.lastPathComponent.dropLast(ext.count + 1))
        var n = 1
        while true {
            let stem: String
            switch style {
            case .copy: stem = n == 1 ? "\(base) - Copy" : "\(base) - Copy (\(n))"
            case .keepBoth: stem = "\(base) (\(n + 1))"
            }
            let candidate = url.deletingLastPathComponent().appending(path: ext.isEmpty ? stem : "\(stem).\(ext)")
            if !(await fs.exists(candidate)) { return candidate }
            n += 1
        }
    }
}
