import SwiftUI

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings()
            case .shortcuts: ShortcutSettings()
            case .advanced: AdvancedSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, shortcuts, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .shortcuts: "Shortcuts"
        case .advanced: "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .shortcuts: "keyboard"
        case .advanced: "gearshape.2"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("reopenLastFolder", store: Prefs.defaults) private var reopenLastFolder = true

    var body: some View {
        @Bindable var view = model.view
        Section("Start") {
            Toggle("Open the last folder when Pane starts", isOn: $reopenLastFolder)
        }
        Section("Folders") {
            Toggle("Show folders first", isOn: $view.foldersFirst)
        }
        Section("Open folders") {
            Toggle("Use Pane to open folders", isOn: Binding(
                get: { model.usePaneForFolders },
                set: { on in Task { await model.setUsePaneForFolders(on) } }))
            Text("Folders other apps open, like Show in Finder from a download, open in Pane. Finder still handles the Desktop and the Trash. If Finder still opens one, turn this off and on again. Turning it off puts back what was set before.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section("Permissions") {
            LabeledContent("Full Disk Access") {
                HStack(spacing: Space.sm) {
                    Text(Permissions.hasFullDiskAccess ? "Allowed" : "Not allowed").foregroundStyle(.secondary)
                    Button("Open System Settings") { Permissions.openFullDiskAccess() }
                }
            }
        }
    }
}

struct ShortcutSettings: View {
    var body: some View {
        @Bindable var hotKey = GlobalHotKey.shared
        Section("Open Pane from anywhere") {
            Toggle("Use a shortcut to open a new tab in Pane", isOn: $hotKey.isEnabled)
            LabeledContent("Shortcut") { ShortcutRecorder(hotKey: hotKey) }
                .disabled(!hotKey.isEnabled)
            if let problem = hotKey.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
            } else {
                Text("Pane has to be running. The shortcut brings it forward with a new tab.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        Section("In Pane") {
            ForEach(Self.keys, id: \.0) { key in
                LabeledContent(key.0) { Text(key.1).foregroundStyle(.secondary) }
            }
        }
    }

    private static let keys: [(String, String)] = [
        ("Rename", "F2"), ("Open", "Return or ⌘↓"), ("Search", "F3 or ⌘F"), ("Edit the address", "F4 or ⌘L"),
        ("Move to Trash", "Delete or ⌘Delete"), ("Cut, Copy, Paste", "⌘X, ⌘C, ⌘V"),
        ("New tab", "⌘T"), ("Go to tab", "⌘1 to ⌘9"), ("Preview pane", "⇧⌘P"),
    ]
}

struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var view = model.view
        Section("Keys") {
            Picker("Return key", selection: $view.returnRenames) {
                Text("Opens the item").tag(false)
                Text("Renames the item").tag(true)
            }
            Text("Opens is how Explorer works. Renames is how Finder works. Command-Down always opens, and F2 always renames.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section("Items") {
            Toggle("Show file extensions", isOn: $view.showExtensions)
            Toggle("Show hidden items", isOn: $view.showHidden)
        }
        Section("Servers") {
            Button("Forget Trusted SFTP Servers…") { model.connections.forgetTrustedServers() }
            Text("Pane asks \u{201C}Trust this server?\u{201D} again the next time you connect to each one.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
