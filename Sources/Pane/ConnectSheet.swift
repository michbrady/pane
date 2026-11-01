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
    @State private var accessKey = ""
    @State private var region = "us-east-1"
    @State private var endpoint = ""

    var body: some View {
        @Bindable var connections = model.connections
        return VStack(alignment: .leading, spacing: Space.lg) {
            Text("Connect to Server").font(.headline)
            Picker("Type", selection: $connections.kind) {
                ForEach(Connections.Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .onChange(of: connections.kind) { model.connections.clearConnectError() }
            VStack(alignment: .leading, spacing: Space.sm) {
                switch model.connections.kind {
                case .share:
                    TextField("Server Address", text: $address, prompt: Text("smb://nas/photos"))
                        .onSubmit(connect)
                    TextField("Name", text: $user)
                    SecureField("Password", text: $password)
                        .onSubmit(connect)
                    Toggle("Remember this password in my Keychain", isOn: $remember)
                case .s3:
                    TextField("Access Key", text: $accessKey)
                    SecureField("Secret Key", text: $password)
                        .onSubmit(connect)
                    TextField("Region", text: $region, prompt: Text("us-east-1"))
                    TextField("Endpoint", text: $endpoint, prompt: Text("Optional, like minio.local:9000"))
                    Toggle("Remember in my Keychain", isOn: $remember)
                }
            }
            .textFieldStyle(.roundedBorder)
            if let error = model.connections.connectError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if connections.kind == .share, !model.connections.recentServers.items.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        Text("Recent Servers").font(.callout.bold())
                        Spacer()
                        Button("Clear Recents") { model.connections.clearRecentServers() }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                    ForEach(model.connections.recentServers.items, id: \.self) { server in
                        Button(server) { address = server }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                }
            }
            HStack {
                if model.connections.isConnecting {
                    ProgressView().controlSize(.small)
                    Text("Connecting…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { model.connections.closeConnectSheet() }
                    .keyboardShortcut(.cancelAction)
                Button("Connect", action: connect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.connections.isConnecting)
            }
        }
        .padding(Space.xl)
        .frame(width: Layout.sheetWidth)
        .noInitialFocus()
    }

    private func connect() {
        switch model.connections.kind {
        case .share: model.connections.connect(address: address, user: user, password: password, remember: remember)
        case .s3: model.connections.connectS3(accessKey: accessKey, secretKey: password, region: region, endpoint: endpoint, remember: remember)
        }
    }
}
