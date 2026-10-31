import AppKit
import PaneKit

/// Self-test for agents: runs the app's real functions on a throwaway home
/// folder, prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_HOME=/tmp/Pane-self-home ~/Applications/Pane.app/Contents/MacOS/Pane --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Locations.isOverridden, Locations.home.path.hasPrefix("/tmp/") || Locations.home.path.hasPrefix("/private/tmp/") else {
            print("SELFTEST refused: set APP_HOME to a folder in /tmp")
            finish(code: 1)
            return
        }
        Task {
            let home = Locations.home
            let fm = FileManager.default
            let work = home.appending(path: "Documents/Work", directoryHint: .isDirectory)
            let docs = home.appending(path: "Documents", directoryHint: .isDirectory)
            try? fm.createDirectory(at: work, withIntermediateDirectories: true)
            try? Data("hello".utf8).write(to: docs.appending(path: "Notes.txt"))
            try? Data("x".utf8).write(to: docs.appending(path: "file10.txt"))
            try? Data("x".utf8).write(to: docs.appending(path: "file2.txt"))

            model.go(to: docs)
            try? await Task.sleep(for: .seconds(0.5))
            check("a folder lists its items", model.items.count >= 4, "\(model.items.count) items")
            check("folders come first", model.items.first?.isFolder == true)
            let names = model.items.map(\.name)
            check("names sort naturally", (names.firstIndex(of: "file2.txt") ?? 0) < (names.firstIndex(of: "file10.txt") ?? 0))

            model.open([work])
            try? await Task.sleep(for: .seconds(0.3))
            check("open on a folder shows its contents", model.currentFolder.path == work.standardizedFileURL.path)
            check("Back is available", model.canGoBack)
            model.goUp()
            check("Go up shows the parent", model.currentFolder.path == docs.standardizedFileURL.path)
            model.goBack()
            check("Go back returns to the last folder", model.currentFolder.path == work.standardizedFileURL.path)
            model.goForward()
            check("Go forward returns", model.currentFolder.path == docs.standardizedFileURL.path)

            model.beginEditingAddress()
            check("the address field shows ~ paths", model.addressText == "~/Documents", model.addressText)
            model.addressText = "~/Documents/Work"
            model.commitAddress()
            try? await Task.sleep(for: .seconds(0.2))
            check("a typed path goes there", model.currentFolder.path == work.standardizedFileURL.path)
            model.beginEditingAddress()
            model.addressText = "~/Nope"
            model.commitAddress()
            check("a bad path shows an error and stays", model.addressError != nil && model.isEditingAddress)
            model.cancelEditingAddress()
            check("Escape restores the breadcrumbs", !model.isEditingAddress)

            check("the tree follows the current folder", model.navSelection == "home:" + work.standardizedFileURL.path, model.navSelection ?? "nil")
            check("the tree opens the folders above", model.expanded.contains("home:" + docs.standardizedFileURL.path))

            try? Data("new".utf8).write(to: work.appending(path: "Added.txt"))
            try? await Task.sleep(for: .seconds(2))
            check("a file added from outside appears", model.items.contains { $0.name == "Added.txt" })

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
