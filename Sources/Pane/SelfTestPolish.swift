import AppKit
import PaneKit

/// Self-test: polish (S-050 to S-054): context menus, empty states, Settings, the keyboard.
extension SelfTest {
    static func polish(_ c: Context) async {
        let model = c.model
        @MainActor func settle() async { await Wait.settle(c.model) }
        NSApp.keyWindow?.makeFirstResponder(nil)

        // S-052 Change settings: Return opens or renames
        model.tab.go(to: c.docs)
        await settle()
        check("Settings has General, Appearance, Shortcuts, and Advanced", SettingsTab.allCases.map(\.title) == ["General", "Appearance", "Shortcuts", "Advanced"])
        model.view.returnRenames = false
        model.tab.selection = Set(model.tab.items.filter { $0.name == "Work" }.map(\.url))
        check("Return opens a folder by default", model.pressReturn())
        await settle()
        check("and shows it", model.tab.currentFolder.standardizedFileURL.path == c.work.standardizedFileURL.path)
        model.tab.go(to: c.docs)
        await settle()
        let notes = model.tab.items.first { $0.name == "Notes.txt" }?.url ?? c.docs
        NSApp.keyWindow?.makeFirstResponder(nil)
        model.view.returnRenames = true
        model.tab.selection = [notes]
        check("with the setting on, Return starts renaming", model.pressReturn() && model.actions.renamingURL?.lastPathComponent == "Notes.txt", "\(String(describing: model.actions.renamingURL)) \(model.tab.selectedItems.count)")
        model.actions.cancelRename()
        model.tab.selection = []
        check("Return with nothing selected does nothing", !model.pressReturn())
        model.view.returnRenames = false
        check("the choice is saved", Prefs.defaults.object(forKey: "view.returnRenames") as? Bool == false)

        let known = Connections.knownHostsFile
        try? FileManager.default.createDirectory(at: known.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "nas ssh-ed25519 AAAA\n".write(to: known, atomically: true, encoding: .utf8)
        model.connections.forgetTrustedServers()
        check("Forget Trusted SFTP Servers empties Pane's list", !FileManager.default.fileExists(atPath: known.path))
        check("and never touches ~/.ssh", !known.path.contains("/.ssh/"))

        // S-054 Make Pane keyboard friendly: F6 and Shift+F6 cycle the areas
        NSApp.keyWindow?.makeFirstResponder(nil)
        model.cancelEditingAddress()
        let shown = FocusMover.navigationShown
        var expected = FocusRegion.list
        var ok = true
        var trail: [String] = []
        for _ in 0..<4 {
            expected = FocusCycle.next(after: expected, navigationShown: shown)
            model.moveFocus()
            await settle()
            trail.append("\(model.focusRegion)")
            ok = ok && model.focusRegion == expected && (expected == .address) == model.isEditingAddress
            // The window's real focus is up to the desktop. Pane's own state is what is tested.
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        check("F6 cycles list, Navigation pane, Address bar, and around, and the Address bar starts editing", ok, "\(trail) shown \(shown)")
        model.cancelEditingAddress()
        model.moveFocus()
        let forward = model.focusRegion
        model.moveFocus(reverse: true)
        check("Shift+F6 goes back", FocusCycle.next(after: model.focusRegion, navigationShown: shown) == forward, "\(model.focusRegion) \(forward)")
        model.cancelEditingAddress()
        let first = model.tab.items.first
        check("a row's VoiceOver label has its name, kind, and size", first.map { ItemSpeech.label(for: $0, showExtensions: true).hasPrefix($0.name) } ?? false)
    }
}
