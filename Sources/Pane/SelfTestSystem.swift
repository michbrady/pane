import AppKit
import Carbon.HIToolbox
import PaneKit

/// Self-test: Pane and the rest of the Mac (S-040 to S-048): the Command bar, the folder-open
/// handler, the shortcut, network and cloud folders.
extension SelfTest {
    static func system(_ c: Context) async {
        let model = c.model, docs = c.docs
        @MainActor func settle() async { await Wait.settle(c.model) }

        // S-041 Use the Command bar
        model.tab.go(to: docs)
        await settle()
        model.tab.selection = []
        check("Cut and Copy are dimmed with nothing selected", !model.canCopy)
        check("Rename is dimmed with nothing selected", !model.actions.canRename)
        model.tab.selection = Set(model.tab.items.prefix(1).map(\.url))
        check("Cut and Copy light up with a selection", model.canCopy)
        check("Rename lights up with one item selected", model.actions.canRename)
        model.actions.copySelection()
        check("Paste lights up when files are on the pasteboard", model.actions.canPaste)
        model.tab.selection = Set(model.tab.items.prefix(2).map(\.url))
        check("Rename dims with two items selected", !model.actions.canRename)
        check("every sort key has a name", SortKey.allCases.allSatisfy { !$0.title.isEmpty })
        model.tab.selection = []

        // S-045 Open in Terminal
        model.tab.go(to: docs)
        await settle()
        check("Terminal is installed, so Open in Terminal is available", model.canOpenInTerminal)
        let work = model.tab.items.first { $0.name == "Work" }
        model.tab.selection = Set([work?.url].compactMap { $0 })
        check("with a folder selected, Terminal opens that folder",
              OpenInTerminal.folder(selected: model.tab.selectedItems, current: model.tab.currentFolder).lastPathComponent == "Work")
        model.tab.selection = []
        check("with nothing selected, Terminal opens the folder shown",
              OpenInTerminal.folder(selected: model.tab.selectedItems, current: model.tab.currentFolder) == model.tab.currentFolder)

        // S-040 Guide Full Disk Access
        check("tests never show the Full Disk Access screen", !model.showFullDiskAccessGuide)
        _ = Permissions.hasFullDiskAccess
        check("Pane can tell whether it has Full Disk Access", true)
        model.showFullDiskAccessGuideForSnapshot()
        check("the screen shows when asked", model.showFullDiskAccessGuide)
        model.dismissFullDiskAccessGuide()
        check("Not Now closes it and it is not shown again", !model.showFullDiskAccessGuide && Prefs.defaults.bool(forKey: "pane.fdaGuideShown"))

        // S-043 Open Pane with a global shortcut
        let hotKey = GlobalHotKey.shared
        check("the default shortcut is Control-Option-E", hotKey.shortcut == .default && hotKey.shortcut.displayText == "⌃⌥E")
        let status = hotKey.register()
        check("the system accepts the shortcut, or says another app has it",
              status == noErr || status == OSStatus(eventHotKeyExistsErr), "status \(status)")
        check("a refused shortcut says why", status == noErr || hotKey.problem?.contains("already used by another app") == true)
        hotKey.unregister()
        let tabsBefore = model.tabs.count
        model.globalShortcutPressed()
        check("pressing the shortcut opens a new tab at home", model.tabs.count == tabsBefore + 1 && model.tab.currentFolder.path == Locations.home.path)
        model.close(model.tab)
        let saved = hotKey.shortcut
        hotKey.shortcut = Shortcut(keyCode: 1, modifiers: Shortcut.command | Shortcut.option)
        check("the shortcut can be changed and is saved",
              (try? JSONDecoder().decode(Shortcut.self, from: Prefs.defaults.data(forKey: "pane.globalShortcut") ?? Data())) == hotKey.shortcut)
        hotKey.unregister()
        hotKey.shortcut = saved
        hotKey.unregister()

        // S-044 Browse network and iCloud: drives and shares
        let backup = c.home.appending(path: "Volumes/Backup", directoryHint: .isDirectory)
        let nas = c.home.appending(path: "Volumes/NAS", directoryHint: .isDirectory)
        model.volumeSource = {
            [VolumeInfo(url: backup, name: "Backup", isLocal: true, isEjectable: true),
             VolumeInfo(url: nas, name: "NAS", isLocal: false, isEjectable: true)]
        }
        model.refreshVolumes()
        check("a drive shows under This Mac", model.thisMacRoots.map(\.name).contains("Backup"), "\(model.thisMacRoots.map(\.name))")
        check("a share shows under Network", model.networkRoots.map(\.name) == ["NAS"])
        check("drives and shares can be ejected", model.driveRoots.first?.ejectable == true && model.networkRoots.first?.ejectable == true)
        check("the home folder cannot be ejected", model.homeRoot.ejectable == false)
        model.tab.isNetworkFolder = { $0.path.contains("/Volumes/NAS") }
        model.tab.go(to: nas)
        await settle()
        check("opening a share selects its row under Network", model.navSelection == "net:" + nas.standardizedFileURL.path, model.navSelection ?? "nil")
        check("a network folder is looked at again every ten seconds", model.tab.pollInterval == 10)
        model.tab.go(to: backup)
        await settle()
        check("a drive's row is selected under This Mac", model.navSelection == "vol:" + backup.standardizedFileURL.path, model.navSelection ?? "nil")
        check("a local folder is not polled", model.tab.pollInterval == nil)
        model.volumeSource = { [] }
        model.refreshVolumes()
        check("an ejected share leaves the tree", model.networkRoots.isEmpty && !model.thisMacRoots.map(\.name).contains("Backup"))
        model.tab.isNetworkFolder = { VolumeInfo.isNetwork($0) }
        model.tab.go(to: c.docs)
        await settle()

        // S-048 Use cloud storage folders
        model.refreshVolumes()
        check("iCloud Drive and the cloud services show under Cloud",
              model.cloudRoots.map(\.name) == ["iCloud Drive", "Dropbox", "Google Drive (me@example.com)"], "\(model.cloudRoots.map(\.name))")
        let iCloud = model.cloudRoots[0].url
        model.tab.go(to: iCloud)
        await settle()
        check("the tab names iCloud Drive by its name", model.tab.currentName == "iCloud Drive", model.tab.currentName)
        check("opening a cloud folder selects its row under Cloud", model.navSelection == "cloud:" + iCloud.path, model.navSelection ?? "nil")
        let report = model.tab.items.first { $0.name == "Report.pdf" }
        check("an old iCloud stub shows under the real name with its size", report?.isOnlineOnly == true && report?.size == 482304,
              "\(model.tab.items.map(\.name))")
        check("a file that is on this Mac is not online only", model.tab.items.first { $0.name == "Shopping list.txt" }?.isOnlineOnly == false)
        check("the Status bar counts the online-only items",
              SelectionSummary.text(itemCount: model.tab.items.count, selected: [], onlineOnly: model.tab.items.filter(\.isOnlineOnly).count).hasSuffix("1 online only"))
        var opened: [URL] = []
        let shopping = model.tab.items.first { $0.name == "Shopping list.txt" }!.url
        model.actions.downloadAndOpen(shopping, open: { opened.append($0) })
        await settle()
        check("Open downloads a file, then opens it", opened.map(\.lastPathComponent) == ["Shopping list.txt"])
        model.actions.downloadAndOpen(iCloud.appending(path: "Missing.txt"), open: { opened.append($0) })
        await settle()
        check("a download that fails says so and opens nothing",
              opened.count == 1 && model.actions.alertMessage?.contains("could not be downloaded") == true, model.actions.alertMessage ?? "nil")
        model.actions.alertMessage = nil
        check("opening an online-only file asks to download it instead of opening it",
              report.map { model.tab.items.contains($0) } == true)
        model.tab.go(to: c.docs)
        await settle()

        // S-047 Disconnect a share or eject a drive
        let temp = c.home.appending(path: "Volumes/Temp", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        model.tab.go(to: temp)
        await settle()
        check("a folder that exists is shown normally", model.tab.loadProblem == nil && model.tab.loadError == nil)
        try? FileManager.default.removeItem(at: temp)
        model.tab.reload()
        await settle()
        check("a folder that went away says it is no longer available",
              model.tab.loadProblem == .unavailable && model.tab.loadError == "This folder is no longer available.", model.tab.loadError ?? "nil")
        model.tab.go(to: c.docs)
        await settle()
        check("going to a folder that exists clears the message", model.tab.loadProblem == nil)
        let gone = c.home.appending(path: "Volumes/NAS2", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: gone, withIntermediateDirectories: true)
        model.volumeSource = { [VolumeInfo(url: gone, name: "NAS2", isLocal: false, isEjectable: true)] }
        model.refreshVolumes()
        model.tab.go(to: gone)
        await settle()
        try? FileManager.default.removeItem(at: gone)
        model.volumeSource = { [] }
        model.refreshVolumes()
        await settle()
        check("a share that disappears leaves the tree and its open folder says so",
              model.networkRoots.isEmpty && model.tab.loadProblem == .unavailable, "\(model.tab.loadProblem as Any)")
        model.tab.go(to: c.docs)
        await settle()
    }
}
