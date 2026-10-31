import Foundation
import PaneKit

/// Spotlight through `NSMetadataQuery`. It must run on the main thread, so the query lives
/// on the main actor. A folder Spotlight does not index just answers with nothing, and the
/// search falls back to scanning the folder.
struct SystemSpotlight: SpotlightSearching {
    func search(_ text: String, in folder: URL) async -> [URL] {
        await MainActor.run { SpotlightQuery() }.run(text, in: folder)
    }
}

@MainActor
private final class SpotlightQuery {
    private let query = NSMetadataQuery()
    private var observer: NSObjectProtocol?
    private var continuation: CheckedContinuation<[URL], Never>?

    func run(_ text: String, in folder: URL) async -> [URL] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            }
            query.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, text)
            query.searchScopes = [folder.path]
            query.start()
            // Do not wait on a folder that never finishes gathering.
            Task {
                try? await Task.sleep(for: .seconds(2))
                finish()
            }
        }
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        query.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        let paths = (0..<query.resultCount).compactMap {
            (query.result(at: $0) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String
        }
        continuation.resume(returning: paths.map { URL(fileURLWithPath: $0) })
    }
}
