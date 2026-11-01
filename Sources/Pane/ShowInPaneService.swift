import AppKit
import PaneKit

/// The Services menu entry "Show in Pane". Other apps list it under Services in their right-click menu
/// for files, and for selected text that is a path. A file shows in its folder, selected. A folder opens.
/// Apps decide for themselves whether they offer Services, so it is not in every menu.
final class ShowInPaneService: NSObject {
    /// Where the items go. The window sets it through the app delegate; a test gives its own.
    var open: ([URL]) -> Void = { urls in AppDelegate.shared?.application(NSApp, open: urls) }

    @objc func showInPane(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let urls = Self.items(on: pasteboard) else {
            error.pointee = "Pane found no file or folder in that." as NSString
            return
        }
        open(urls)
    }

    /// The files on the pasteboard, or the paths in its text that exist. nil when there are none.
    static func items(on pasteboard: NSPasteboard) -> [URL]? {
        var urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if urls.isEmpty, let text = pasteboard.string(forType: .string) {
            urls = ServicePaths.urls(fromText: text, home: NSHomeDirectory()).filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        return urls.isEmpty ? nil : urls
    }
}
