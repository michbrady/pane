import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            NavigationPane()
                .navigationSplitViewColumnWidth(
                    min: Layout.navigationMin, ideal: Layout.navigationIdeal, max: Layout.navigationMax)
        } detail: {
            FolderPage()
        }
        .navigationTitle(model.currentName)
        .noInitialFocus()
        .sheet(isPresented: .init(get: { model.progressVisible }, set: { _ in })) {
            OperationSheet()
        }
        .alert("Pane", isPresented: .init(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.alertMessage ?? "")
        }
        .background(FrameAutosave(name: "PaneMain"))
        .task {
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }
}

/// The content column: Address bar, Details view, Status bar, and the Command bar.
struct FolderPage: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            AddressBar()
            Divider()
            DetailsView()
            Divider()
            StatusBar()
        }
        // The Search box and the Command bar show their place now. Search (S-030)
        // and the commands (S-041) come in later stories, so they stay dimmed.
        .background {
            // F4 focuses the Address bar, like Explorer. Cmd-L is in the Go menu.
            Button("Go to Address") { model.beginEditingAddress() }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF4FunctionKey)!)), modifiers: [])
                .opacity(0)
                .accessibilityHidden(true)
        }
        .searchable(text: $search, prompt: "Search")
        .toolbar { CommandBar() }
    }
}

/// Explorer's Command bar as the window toolbar. Items dim until their stories land.
private struct CommandBar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItemGroup {
            Menu("New", systemImage: "plus") {
                Button("Folder") {}
                Button("File") {}
            }
            .help("Make a new folder or file (⇧⌘N)")
            .disabled(true)
            Button("Cut", systemImage: "scissors") {}
                .help("Cut the selected items (⌘X)")
                .disabled(true)
            Button("Copy", systemImage: "doc.on.doc") {}
                .help("Copy the selected items (⌘C)")
                .disabled(true)
            Button("Paste", systemImage: "doc.on.clipboard") {}
                .help("Paste the items here (⌘V)")
                .disabled(true)
            Button("Rename", systemImage: "pencil") {}
                .help("Rename the selected item (F2)")
                .disabled(true)
            Button("Move to Trash", systemImage: "trash") {}
                .help("Move the selected items to the Trash (⌫)")
                .disabled(true)
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Menu("Sort", systemImage: "arrow.up.arrow.down") {}
                .help("Choose how items are ordered")
                .disabled(true)
            Menu("View", systemImage: "list.bullet") {}
                .help("Choose how items are shown")
                .disabled(true)
        }
    }
}

/// Shows a long copy or move: what is happening, how far along, and Cancel.
struct OperationSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(title).font(.headline)
            if let p = model.progress {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                Text(p.current).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.cancelOperation() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Space.xl)
        .frame(width: Layout.sheetWidth)
        .noInitialFocus()
    }

    private var title: String {
        guard let p = model.progress else { return model.progressTitle + "…" }
        return "\(model.progressTitle) \(min(p.done + 1, p.total)) of \(p.total)"
    }
}
