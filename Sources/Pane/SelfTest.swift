import AppKit
import PaneKit

/// Self-test for agents: runs the app's real functions on a throwaway home
/// folder, prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_HOME=/tmp/Pane-self-home /Applications/Pane.app/Contents/MacOS/Pane --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    /// The folders the sections share, all inside the throwaway home folder.
    struct Context {
        let model: AppModel
        let home: URL
        let docs: URL
        let work: URL
        let drop: URL
    }

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
            let context = Context(model: model, home: home, docs: docs, work: work,
                                  drop: home.appending(path: "Conflicts", directoryHint: .isDirectory))
            await browse(context)
            await files(context)
            await views(context)
            await find(context)
            await system(context)
            await remote(context)
            await polish(context)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
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
