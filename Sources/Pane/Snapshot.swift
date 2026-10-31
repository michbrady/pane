import AppKit
import IOKit.pwr_mgt
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
        case window, tree, addressEdit = "address-edit", addressError = "address-error", emptyFolder = "empty-folder", progress, cut, conflict

        @MainActor func show(in model: AppModel) {
            let home = Locations.home
            model.cancelEditingAddress()
            model.hideProgressForSnapshot()
            model.hideConflictForSnapshot()
            switch self {
            case .window:
                model.go(to: home.appending(path: "Documents", directoryHint: .isDirectory))
            case .tree:
                model.go(to: home.appending(path: "Documents/Work", directoryHint: .isDirectory))
            case .addressEdit:
                model.go(to: home.appending(path: "Documents", directoryHint: .isDirectory))
                model.beginEditingAddress()
            case .addressError:
                model.beginEditingAddress()
                model.addressText = "~/Nope"
                model.commitAddress()
            case .emptyFolder:
                model.go(to: home.appending(path: "Empty", directoryHint: .isDirectory))
            case .cut:
                model.go(to: home.appending(path: "Documents", directoryHint: .isDirectory))
                let docs = home.appending(path: "Documents", directoryHint: .isDirectory)
                model.selection = [docs.appending(path: "Notes.txt"), docs.appending(path: "Budget 2026.xlsx")]
                model.cutSelection()
                model.selection = [docs.appending(path: "Trip itinerary.pdf")]
            case .conflict:
                let docs = home.appending(path: "Documents", directoryHint: .isDirectory)
                model.go(to: docs.appending(path: "Work", directoryHint: .isDirectory))
                model.showConflictForSnapshot(incoming: docs.appending(path: "Notes.txt"),
                                              existing: docs.appending(path: "Read me first.md"))
            case .progress:
                model.go(to: home.appending(path: "Documents", directoryHint: .isDirectory))
                model.showProgressForSnapshot()
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
            // An open sheet refuses terminate, and the run would wait forever.
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
