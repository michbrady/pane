import SwiftUI
import UniformTypeIdentifiers

/// Receives files dropped on a folder: in the Details view, the Navigation pane,
/// or the breadcrumbs. The cursor badge says copy or move before the drop.
struct FileDropDelegate: DropDelegate {
    let model: AppModel
    let folder: URL

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: model.dropMode(into: folder) == .copy ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await provider.fileURL() { urls.append(url) }
            }
            model.drop(urls, into: folder)
        }
        return true
    }
}

extension NSItemProvider {
    func fileURL() async -> URL? {
        await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }
}

extension View {
    /// Makes a folder row accept dropped files.
    func acceptsFileDrops(into folder: URL, model: AppModel) -> some View {
        onDrop(of: [.fileURL], delegate: FileDropDelegate(model: model, folder: folder))
    }
}
