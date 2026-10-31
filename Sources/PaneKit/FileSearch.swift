import Foundation

/// Spotlight, as far as search needs it: file paths whose names contain some text, below a folder.
/// The app plugs in the real thing. Tests plug in a fake.
public protocol SpotlightSearching: Sendable {
    func search(_ text: String, in folder: URL) async -> [URL]
}

/// Finds files by name in a folder and everything below it. Results stream in as they are found.
public enum FileSearch {
    /// Uses Spotlight when it knows the folder and returns something. Otherwise it scans the
    /// folder tree itself, which also covers folders and drives Spotlight does not index.
    public static func results(for text: String, in folder: URL, spotlight: SpotlightSearching?,
                               showHidden: Bool) -> AsyncStream<[FolderItem]> {
        AsyncStream { continuation in
            let task = Task {
                if let spotlight {
                    let found = await spotlight.search(text, in: folder)
                        .filter { showHidden || !isHidden($0, below: folder) }
                        .compactMap { FolderLister.item(at: $0) }
                    if !found.isEmpty, !Task.isCancelled {
                        continuation.yield(found)
                        continuation.finish()
                        return
                    }
                }
                await scan(text, in: folder, showHidden: showHidden) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Walks the tree and reports matches in batches of up to 50. Stops when the task is cancelled.
    static func scan(_ text: String, in folder: URL, showHidden: Bool, report: ([FolderItem]) -> Void) async {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !showHidden { options.insert(.skipsHiddenFiles) }
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: options,
                                                          errorHandler: { _, _ in true }) else { return }
        var batch: [FolderItem] = []
        var visited = 0
        while let url = walker.nextObject() as? URL {
            if Task.isCancelled { return }
            visited += 1
            // Let other work run now and then, so a huge tree never hogs a thread.
            if visited % 500 == 0 { await Task.yield() }
            guard matches(url.lastPathComponent, text), let item = FolderLister.item(at: url) else { continue }
            batch.append(item)
            if batch.count >= 50 { report(batch); batch = [] }
        }
        if !batch.isEmpty { report(batch) }
    }

    /// A name matches when it contains the text, ignoring case and accents.
    public static func matches(_ name: String, _ text: String) -> Bool {
        name.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func isHidden(_ url: URL, below folder: URL) -> Bool {
        let base = folder.standardizedFileURL.pathComponents.count
        return url.standardizedFileURL.pathComponents.dropFirst(base).contains { $0.hasPrefix(".") }
    }
}
