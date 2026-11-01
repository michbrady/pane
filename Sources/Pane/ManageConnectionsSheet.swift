import PaneKit
import SwiftUI

/// Connect to Server > Manage Connections: the saved servers, with Edit and Remove.
struct ManageConnectionsSheet: View {
    let model: AppModel
    @State private var removing: SavedConnection?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Manage Connections").font(.headline)
            if model.connections.saved.items.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("No saved connections").font(.callout.bold())
                    Text("Turn on Save this connection when you connect to a server, and it shows up here and under Connections.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: Space.sm) {
                        ForEach(model.connections.saved.items) { row($0) }
                    }
                }
                .frame(maxHeight: 280)
            }
            HStack {
                Button("Connect to Server…") { model.connections.openConnectSheet() }
                Spacer()
                Button("Done") { model.connections.showManageSheet = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: Layout.sheetWidth)
        .noInitialFocus()
        .confirmationDialog("Remove \u{201C}\(removing?.displayName ?? "")\u{201D}?", isPresented: .init(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { connection in
            Button("Remove", role: .destructive) { model.removeSavedConnection(connection.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its saved password is deleted from your Keychain.")
        }
    }

    private func row(_ connection: SavedConnection) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: connection.kind.symbol)
                .frame(width: Layout.rowIcon, height: Layout.rowIcon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(connection.displayName).lineLimit(1)
                Text("\(connection.detail) · \(connection.kind.title)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.router.serverKeys.contains(connection.serverKey) {
                Text("Connected").font(.callout).foregroundStyle(.secondary)
            }
            Button("Edit…") { model.connections.openEdit(connection) }
            Button("Remove", role: .destructive) { removing = connection }
        }
    }
}
