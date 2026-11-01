import AppKit
import IOKit.pwr_mgt
import PaneKit
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots ~/Applications/Pane.app/Contents/MacOS/Pane
/// writes <page>-light.png and <page>-dark.png for every snapshot page (SnapshotPage), and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=window,tree limits the pages. Add "settings" to include Settings.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    /// The views to capture. Add a case when a story adds a view.
    enum Page: String, CaseIterable {
        case window, tree, addressEdit = "address-edit", addressError = "address-error", emptyFolder = "empty-folder", progress, transfer, cut, conflict, deleteConfirm = "delete-confirm", rename, sorted, tabs, list, icons, columns, properties, preview, network, cloud, unavailable, connect, connectS3 = "connect-s3", connectFTP = "connect-ftp", connectSFTP = "connect-sftp", connectSFTPTrust = "connect-sftp-trust", remote, remoteLost = "remote-lost", remoteDelete = "remote-delete", remoteEdit = "remote-edit", savedConnections = "saved-connections", manageConnections = "manage-connections", onboarding, search, searchEmpty = "search-empty", previewImage = "preview-image", previewPDF = "preview-pdf"

        @MainActor func show(in model: AppModel) {
            let home = Locations.home
            model.cancelEditingAddress()
            model.actions.hideProgressForSnapshot()
            model.actions.hideEditConflictForSnapshot()
            model.actions.hideConflictForSnapshot()
            model.actions.pendingDelete = nil
            model.actions.cancelRename()
            model.view.reset()
            model.tab.endSearch(reload: false)
            model.closeProperties()
            model.dismissFullDiskAccessGuide()
            for key in model.router.serverKeys { model.disconnect(serverKey: key) }
            model.connections.closeConnectSheet()
            model.connections.showManageSheet = false
            model.connections.savedForSnapshot([])
            if self != .network { model.places.volumeSource = { [] }; model.places.refreshVolumes() }
            model.closeOtherTabs(except: model.tab)
            switch self {
            case .window:
                model.tab.go(to: home.appending(path: "Documents", directoryHint: .isDirectory))
            case .tree:
                model.tab.go(to: home.appending(path: "Documents/Work", directoryHint: .isDirectory))
            case .addressEdit:
                model.tab.go(to: home.appending(path: "Documents", directoryHint: .isDirectory))
                model.beginEditingAddress()
            case .addressError:
                model.beginEditingAddress()
                model.addressText = "~/Nope"
                model.commitAddress()
            case .emptyFolder:
                model.tab.go(to: home.appending(path: "Empty", directoryHint: .isDirectory))
            case .cut:
                model.tab.go(to: home.appending(path: "Documents", directoryHint: .isDirectory))
                let docs = home.appending(path: "Documents", directoryHint: .isDirectory)
                model.tab.selection = [docs.appending(path: "Notes.txt"), docs.appending(path: "Budget 2026.xlsx")]
                model.actions.cutSelection()
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    model.tab.selection = Set(model.tab.items.filter { $0.name == "Trip itinerary.pdf" }.map(\.url))
                }
            case .conflict:
                let docs = home.appending(path: "Documents", directoryHint: .isDirectory)
                model.tab.go(to: docs.appending(path: "Work", directoryHint: .isDirectory))
                model.actions.showConflictForSnapshot(incoming: docs.appending(path: "Notes.txt"),
                                              existing: docs.appending(path: "Read me first.md"))
            case .deleteConfirm:
                let docs = home.appending(path: "Documents", directoryHint: .isDirectory)
                model.tab.go(to: docs)
                model.tab.selection = [docs.appending(path: "Notes.txt"), docs.appending(path: "file2.txt")]
                model.actions.askDeleteImmediately()
            case .rename:
                let docs = home.appending(path: "Documents", directoryHint: .isDirectory)
                model.tab.go(to: docs)
                // Wait for the listing, then choose and start naming, as a person pressing F2 would.
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    model.tab.selection = Set(model.tab.items.filter { $0.name == "Trip itinerary.pdf" }.map(\.url))
                    try? await Task.sleep(for: .milliseconds(200))
                    model.actions.beginRename()
                }
            case .tabs:
                let docs = home.appending(path: "Documents", directoryHint: .isDirectory)
                model.tab.go(to: docs)
                model.newTab(at: home.appending(path: "Pictures", directoryHint: .isDirectory), activate: false)
                model.newTab(at: home.appending(path: "Downloads", directoryHint: .isDirectory), activate: false)
            case .columns:
                let docs = home.appending(path: "Documents", directoryHint: .isDirectory)
                model.tab.go(to: docs)
                var layout = model.view.columns(for: docs)
                layout[visibility: "created"] = .visible
                layout[visibility: "tags"] = .visible
                model.view.setColumns(layout, for: docs)
            case .properties:
                let docs = home.appending(path: "Documents", directoryHint: .isDirectory)
                model.tab.go(to: docs)
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    model.tab.selection = Set(model.tab.items.filter { $0.name == "Trip itinerary.pdf" }.map(\.url))
                    try? await Task.sleep(for: .milliseconds(150))
                    model.showProperties()
                }
            case .preview, .previewImage, .previewPDF:
                let folder = self == .previewImage ? "Pictures" : "Documents"
                let name = self == .previewImage ? "Beach.jpg" : self == .previewPDF ? "Trip itinerary.pdf" : "Notes.txt"
                model.tab.go(to: home.appending(path: folder, directoryHint: .isDirectory))
                model.view.showPreview = true
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    model.tab.selection = Set(model.tab.items.filter { $0.name == name }.map(\.url))
                }
            case .network:
                let backup = home.appending(path: "Volumes/Backup", directoryHint: .isDirectory)
                let nas = home.appending(path: "Volumes/NAS", directoryHint: .isDirectory)
                model.places.volumeSource = {
                    [VolumeInfo(url: backup, name: "Backup", isLocal: true, isEjectable: true),
                     VolumeInfo(url: nas, name: "photos on nas", isLocal: false, isEjectable: true)]
                }
                model.places.refreshVolumes()
                model.tab.go(to: nas)
            case .unavailable:
                let gone = home.appending(path: "Volumes/Gone", directoryHint: .isDirectory)
                try? FileManager.default.createDirectory(at: gone, withIntermediateDirectories: true)
                model.tab.go(to: gone)
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    try? FileManager.default.removeItem(at: gone)
                    model.tab.reload()
                }
            case .connect, .connectS3, .connectFTP, .connectSFTP, .connectSFTPTrust:
                model.tab.go(to: home.appending(path: "Documents", directoryHint: .isDirectory))
                model.connections.kind = self == .connectS3 ? .s3 : self == .connectFTP ? .ftp : (self == .connectSFTP || self == .connectSFTPTrust) ? .sftp : .share
                model.connections.clearRecentServers()
                model.connections.recentServersForSnapshot(["smb://nas/photos", "smb://backup.local/files"])
                model.connections.openConnectSheet()
                model.connections.ftpProtocol = .plain
                if self == .connectSFTPTrust {
                    model.connections.showTrustForSnapshot(host: "nas.local", fingerprint: "SHA256:7vQ2kXc0nR9aYtL3mH8dFhP1uJ4bWzE6sOiTgNxKqAw")
                }
            case .remote, .remoteLost, .remoteDelete, .remoteEdit, .savedConnections, .manageConnections:
                let nas = InMemoryRemote(serverKey: "sftp://nas")
                for folder in ["/Photos", "/Documents", "/Documents/Taxes", "/Backups"] { nas.add(folder: folder) }
                nas.add(file: "/Documents/Budget 2026.xlsx", size: 118_000); nas.add(file: "/Documents/Notes.txt", size: 2_400)
                nas.add(file: "/Documents/Trip itinerary.pdf", size: 1_884_160)
                if self == .savedConnections || self == .manageConnections {
                    model.connections.savedForSnapshot([
                        SavedConnection(kind: .sftp, host: "nas", user: "me"),
                        SavedConnection(kind: .s3, host: "minio.local", port: 9000, user: "AKIAEXAMPLE", region: "us-east-1"),
                        SavedConnection(kind: .ftps, host: "ftp.example.com", user: "web"),
                    ])
                }
                model.connected(nas)
                model.tab.go(to: RemoteURL.make(scheme: "sftp", host: "nas", path: "/Documents"))
                if self == .manageConnections { model.connections.openManageSheet() }
                if self == .savedConnections || self == .manageConnections {
                    // A short tree, so the whole Connections section is in view.
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        model.places.expanded.removeAll()
                    }
                }
                if self == .remoteEdit {
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        model.actions.showStatusForSnapshot("Uploaded Notes.txt")
                        model.actions.showEditConflictForSnapshot(name: "Notes.txt")
                    }
                }
                if self == .remoteDelete {
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        model.tab.selection = Set(model.tab.items.prefix(3).map(\.url))
                        model.actions.askDeleteImmediately()
                    }
                }
                if self == .remoteLost {
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        nas.dropConnection()
                        model.tab.reload()
                    }
                }
            case .cloud:
                model.places.refreshVolumes()
                if let icloud = model.places.cloudRoots.first { model.tab.go(to: icloud.url) }
            case .onboarding:
                model.tab.go(to: home.appending(path: "Documents", directoryHint: .isDirectory))
                model.showFullDiskAccessGuideForSnapshot()
            case .search, .searchEmpty:
                model.tab.go(to: home)
                let text = self == .search ? "budget" : "zzzz"
                model.tab.searchText = text
                model.tab.search(text)
            case .list:
                model.tab.go(to: home.appending(path: "Documents", directoryHint: .isDirectory))
                model.view.mode = .list
            case .icons:
                model.tab.go(to: home.appending(path: "Pictures", directoryHint: .isDirectory))
                model.view.mode = .icons
            case .sorted:
                model.tab.go(to: home.appending(path: "Documents", directoryHint: .isDirectory))
                model.view.setSort(.size, ascending: false)
            case .progress:
                model.tab.go(to: home.appending(path: "Documents", directoryHint: .isDirectory))
                model.actions.showProgressForSnapshot()
            case .transfer:
                model.tab.go(to: home.appending(path: "Documents", directoryHint: .isDirectory))
                model.actions.showTransferProgressForSnapshot()
            }
        }
    }

    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against your real folders or settings.
        guard Locations.isOverridden else {
            print("SNAPSHOT refused: set APP_HOME to a folder in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in Page.allCases where only?.contains(page.rawValue) ?? true {
                    page.show(in: model)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                }
            }
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet or alert refuses terminate, and the run would wait forever.
            model.actions.hideEditConflictForSnapshot()
            model.actions.hideConflictForSnapshot()
            model.actions.hideProgressForSnapshot()
            model.actions.pendingDelete = nil
            try? await Task.sleep(for: .milliseconds(300))
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
