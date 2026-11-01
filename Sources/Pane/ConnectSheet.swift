import PaneKit
import SwiftUI

/// Go > Connect to Server: type `smb://nas/photos`, a name and password, and the share appears under Network.
/// Recent servers are one click away. The password goes to the Keychain only if the person ticks the box.
struct ConnectSheet: View {
    let model: AppModel
    @State private var address = ""
    @State private var user = ""
    @State private var password = ""
    @State private var remember = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Connect to Server").font(.headline)
            VStack(alignment: .leading, spacing: Space.sm) {
                TextField("Server Address", text: $address, prompt: Text("smb://nas/photos"))
                    .onSubmit(connect)
                TextField("Name", text: $user)
                SecureField("Password", text: $password)
                    .onSubmit(connect)
                Toggle("Remember this password in my Keychain", isOn: $remember)
            }
            .textFieldStyle(.roundedBorder)
            if let error = model.connectError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if !model.recentServers.items.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        Text("Recent Servers").font(.callout.bold())
                        Spacer()
                        Button("Clear Recents") { model.clearRecentServers() }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                    ForEach(model.recentServers.items, id: \.self) { server in
                        Button(server) { address = server }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                }
            }
            HStack {
                if model.isConnecting {
                    ProgressView().controlSize(.small)
                    Text("Connecting…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { model.closeConnectSheet() }
                    .keyboardShortcut(.cancelAction)
                Button("Connect", action: connect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isConnecting)
            }
        }
        .padding(Space.xl)
        .frame(width: Layout.sheetWidth)
        .noInitialFocus()
    }

    private func connect() {
        model.connect(address: address, user: user, password: password, remember: remember)
    }
}
