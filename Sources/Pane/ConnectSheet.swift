import AppKit
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
    @State private var host = ""
    @State private var port = ""
    @State private var useKey = false
    @State private var keyPath = ""
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
                case .ftp:
                    Picker("Protocol", selection: $connections.ftpProtocol) {
                        ForEach(Connections.FTPProtocol.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Server", text: $host, prompt: Text("ftp.example.com"))
                    TextField("Port", text: $port, prompt: Text("21"))
                    TextField("User Name", text: $user)
                    SecureField("Password", text: $password)
                        .onSubmit(connect)
                    Toggle("Remember this password in my Keychain", isOn: $remember)
                    if let note = connections.ftpProtocol.note {
                        Label(note, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                case .sftp:
                    TextField("Server", text: $host, prompt: Text("nas.local"))
                    TextField("Port", text: $port, prompt: Text("22"))
                    TextField("User Name", text: $user)
                    Picker("Sign in with", selection: $useKey) {
                        Text("Password").tag(false)
                        Text("Key").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if useKey {
                        HStack {
                            Text(keyPath.isEmpty ? "No key chosen" : URL(fileURLWithPath: keyPath).lastPathComponent)
                                .foregroundStyle(keyPath.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                            Spacer()
                            Button("Choose Key…", action: chooseKey)
                        }
                    }
                    SecureField(useKey ? "Key Passphrase" : "Password", text: $password, prompt: useKey ? Text("Leave empty if the key has none") : nil)
                        .onSubmit(connect)
                    Toggle(useKey ? "Remember the passphrase in my Keychain" : "Remember this password in my Keychain", isOn: $remember)
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
            if let pending = model.connections.pendingTrust {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Label("Trust this server?", systemImage: "lock.shield").font(.callout.bold())
                    Text("Pane has not connected to \(pending.host) before. Check that this fingerprint is the one your server shows.")
                        .font(.callout)
                    Text(pending.fingerprint).font(.callout.monospaced()).textSelection(.enabled)
                    HStack {
                        Button("Trust and Connect") { model.connections.trustPendingServer() }
                        Button("Don't Trust") { model.connections.declinePendingServer() }
                    }
                }
            }
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
        case .ftp: model.connections.connectFTP(host: host, port: port, user: user, password: password, protocol: model.connections.ftpProtocol, remember: remember)
        case .sftp: model.connections.connectSFTP(host: host, port: port, user: user, useKey: useKey, keyPath: keyPath, secret: password, remember: remember)
        case .s3: model.connections.connectS3(accessKey: accessKey, secretKey: password, region: region, endpoint: endpoint, remember: remember)
        }
    }

    /// Starts in `~/.ssh`, where keys live. Hidden folders show, since that folder is one.
    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh", directoryHint: .isDirectory)
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.message = "Choose your private key file."
        if panel.runModal() == .OK, let url = panel.url { keyPath = url.path }
    }
}
