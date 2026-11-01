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
                Button("Quick Look") { model.toggleQuickLook() }
                    .disabled(model.tab.selection.isEmpty)
                Button("Open in Terminal") { model.openInTerminal() }
                    .disabled(!model.canOpenInTerminal)
                Button("Properties") { model.showProperties() }
                    .keyboardShortcut("i")
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
            CommandGroup(after: .textEditing) {
                Button("Find") { model.focusSearch() }
                    .keyboardShortcut("f")
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
            CommandGroup(after: .toolbar) {
                Divider()
                ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { index, mode in
                    Toggle("As \(mode.title)", isOn: Binding(get: { model.view.mode == mode }, set: { _ in model.view.mode = mode }))
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.control, .command])
                }
                Divider()
                Toggle("Show Preview Pane", isOn: Binding(get: { model.view.showPreview }, set: { model.view.showPreview = $0 }))
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Toggle("Show Hidden Items", isOn: Binding(get: { model.view.showHidden }, set: { model.view.showHidden = $0 }))
                    .keyboardShortcut(".", modifiers: [.command, .shift])
                Toggle("Show File Extensions", isOn: Binding(get: { model.view.showExtensions }, set: { model.view.showExtensions = $0 }))
            }
            CommandGroup(replacing: .saveItem) {
                Button("New Tab") { model.newTab() }
                    .keyboardShortcut("t")
                Button("Close Tab") {
                    // The last tab closes the window.
                    if !model.close(model.tab) { NSApp.keyWindow?.performClose(nil) }
                }
                .keyboardShortcut("w")
            }
            CommandGroup(after: .windowArrangement) {
                Divider()
                Button("Show Next Tab") { model.selectNextTab() }
                    .keyboardShortcut(.tab, modifiers: .control)
                Button("Show Previous Tab") { model.selectPreviousTab() }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])
                ForEach(1...9, id: \.self) { number in
                    Button("Go to Tab \(number)") { model.select(number - 1) }
                        .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
                        .disabled(number > model.tabs.count)
                }
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
                Button("Move Focus to Next Area") { model.moveFocus() }
                    .keyboardShortcut(KeyEquivalent("\u{F709}"), modifiers: [])
                Button("Move Focus to Previous Area") { model.moveFocus(reverse: true) }
                    .keyboardShortcut(KeyEquivalent("\u{F709}"), modifiers: .shift)
                    .keyboardShortcut("l")
                Button("Connect to Server…") { model.connections.openConnectSheet() }
                    .keyboardShortcut("k")
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
    static weak var shared: AppDelegate?
    /// Set once the window exists. Items other apps asked Pane to open before then wait in `pending`.
    var onOpen: (([URL]) -> Void)? {
        didSet { if let onOpen, !pending.isEmpty { onOpen(pending); pending = [] } }
    }
    private var pending: [URL] = []

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    /// Another app (or Show in Finder, when Pane opens folders) asked Pane to open these.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let onOpen { onOpen(urls) } else { pending += urls }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quitting first sends what was saved to files opened from a server, and removes their temporary copies.
    var quitWork: (() async -> Bool)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Test and snapshot runs quit from inside a task that holds the main actor, so they cannot wait for a reply.
        guard !Locations.isOverridden, let quitWork else { return .terminateNow }
        Task { @MainActor in NSApp.reply(toApplicationShouldTerminate: await quitWork()) }
        return .terminateLater
    }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}
