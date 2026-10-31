import AppKit
import SwiftUI

// Pane
//   Pane                      the app
//   APP_HOME=<dir> Pane       treat <dir> as the home folder, with throwaway settings (tests, snapshots)
//   APP_START=<dir> Pane      open this folder first
//   APP_SNAPSHOT=<dir> Pane   save a PNG of every snapshot page and Settings tab in light and dark mode, then quit
//   Pane --selftest           run the self-test on a /tmp folder and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> Pane      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 Pane           draw the 8 pt grid and the layout probes over the window

@main
struct PaneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Pane", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {
                Button("Open") { model.tab.openSelection() }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .disabled(model.tab.selection.isEmpty)
                Button("New Folder") { model.actions.newFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Rename") { model.actions.beginRename() }
                    .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF2FunctionKey)!)), modifiers: [])
                    .disabled(!model.actions.canRename)
                Divider()
                Button("Move to Trash") { model.actions.trashSelection() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.tab.selection.isEmpty)
                Button("Delete Immediately…") { model.actions.askDeleteImmediately() }
                    .keyboardShortcut(.delete, modifiers: .shift)
                    .disabled(model.tab.selection.isEmpty)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { model.actions.cutSelection() }
                    .keyboardShortcut("x")
                    .disabled(!model.canCopy)
                Button("Copy") { model.actions.copySelection() }
                    .keyboardShortcut("c")
                    .disabled(!model.canCopy)
                Button("Paste") { model.actions.paste() }
                    .keyboardShortcut("v")
            }
            CommandMenu("Go") {
                Button("Back") { model.tab.goBack() }
                    .keyboardShortcut("[")
                    .disabled(!model.tab.canGoBack)
                Button("Forward") { model.tab.goForward() }
                    .keyboardShortcut("]")
                    .disabled(!model.tab.canGoForward)
                Button("Enclosing Folder") { model.tab.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(!model.tab.canGoUp)
                Divider()
                Button("Go to Address…") { model.beginEditingAddress() }
                    .keyboardShortcut("l")
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}
