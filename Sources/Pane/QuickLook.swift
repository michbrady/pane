import AppKit
import QuickLookUI

/// The system Quick Look panel, fed with the selected items. Space opens and closes it,
/// and the arrow keys move the selection, so the preview follows.
@MainActor
final class QuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    static let shared = QuickLookController()
    weak var model: AppModel?
    private(set) var urls: [URL] = []

    var isVisible: Bool { QLPreviewPanel.shared()?.isVisible ?? false }

    func show(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    /// The selection changed while the panel is open: show the new items.
    func update(_ urls: [URL]) {
        guard isVisible, !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.reloadData()
    }

    func close() {
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    // MARK: Data source

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }

    // MARK: Delegate

    /// The arrow keys, pressed in the panel, move the selection in the list behind it.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, let model else { return false }
        switch event.keyCode {
        case 125, 124: model.tab.moveSelection(by: 1)    // down, right
        case 126, 123: model.tab.moveSelection(by: -1)   // up, left
        default: return false
        }
        return true
    }
}
