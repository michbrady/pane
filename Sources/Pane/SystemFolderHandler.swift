import AppKit
import PaneKit
import UniformTypeIdentifiers

/// The real settings: `NSFileViewer` in the global preferences (what other apps' "Show in Finder"
/// calls) and the default app for folders. Tests use `InMemoryFolderHandlerSystem` instead and
/// never touch these.
final class SystemFolderHandler: FolderHandlerSystem {
    private let key = "NSFileViewer" as CFString

    func fileViewer() -> String? {
        CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
    }

    func setFileViewer(_ bundleID: String?) {
        CFPreferencesSetValue(key, bundleID as CFString?, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    func folderHandler() -> String? {
        NSWorkspace.shared.urlForApplication(toOpen: .folder).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    func setFolderHandler(_ bundleID: String) async {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        try? await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: .folder)
    }
}
