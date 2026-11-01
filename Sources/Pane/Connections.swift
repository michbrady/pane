import Foundation
import Observation
import PaneKit

/// Connecting to servers: the Connect to Server sheet, the recent list, and the mount. SMB today.
/// FTP, SFTP, and S3 connections join here. A connected share appears under Network through `Places`.
@Observable
final class Connections {
    var showConnectSheet = false

    /// The open connections to servers, and this Mac. Every tab reads it to pick a file system for a URL.
    let router = FileSystemRouter(local: LocalFileSystem(
        trashFolder: Locations.isOverridden ? Locations.home.appending(path: ".Trash", directoryHint: .isDirectory) : nil))

    /// What the sheet connects to. More join as they are built.
    enum Kind: String, CaseIterable, Identifiable {
        case share = "File Share (SMB)", ftp = "FTP", sftp = "SFTP", s3 = "Amazon S3"
        var id: String { rawValue }
    }
    var kind = Kind.share

    /// FTP with TLS comes first: it hides the password. Plain FTP says what it gives up.
    enum FTPProtocol: String, CaseIterable, Identifiable {
        case tls = "FTP with TLS", plain = "FTP"
        var id: String { rawValue }
        var note: String? { self == .plain ? "FTP sends your password without encryption." : nil }
    }
    var ftpProtocol = FTPProtocol.tls

    // Saved connections (S-067). Settings only: the secret is in the Keychain.
    var saved = SavedConnections(data: Prefs.defaults.data(forKey: "pane.savedConnections"))
    var showManageSheet = false
    /// What the sheet fills in when opened to edit a saved connection.
    var prefill: SavedConnection?
    var editingID: UUID?
    /// A saved connection that could not be opened: its name, and why.
    var unableToConnect: (name: String, reason: String)?
    /// Called when the saved list changes, so the Navigation pane shows it.
    var savedChanged: () -> Void = {}
    /// Called after each attempt ends, win or lose. Opening a saved connection from the tree waits on it.
    var afterAttempt: (() -> Void)?
    private(set) var isConnecting = false
    private(set) var connectError: String?
    private(set) var recentServers = RecentServers(Prefs.defaults.stringArray(forKey: "pane.recentServers") ?? [])
    /// The real mount and Keychain calls. Tests swap them, so they never reach a network or your Keychain.
    var mounter: (SMBAddress, String?, String?) async -> Result<URL, MountFailure> = { await SMBMount.mount($0, user: $1, password: $2) }
    var savePassword: (String, String, String) -> Void = { PasswordKeychain.save($0, server: $1, account: $2) }
    var savedPassword: (String, String) -> String? = { PasswordKeychain.password(server: $0, account: $1) }
    /// Called with where a new share appeared. AppModel refreshes the places and shows it.
    var didMount: (URL) -> Void = { _ in }
    /// Passwords and secret keys. The Keychain, or memory when a test or snapshot runs.
    var secrets: SecretStore = Locations.isOverridden ? InMemorySecretStore() : KeychainSecretStore()
    /// Builds the file system for a checked form. Tests give one that answers from a script, never the network.
    var makeServer: (ConnectionForm.Valid) -> any RemoteFileSystem = { valid in
        let connection = valid.connection
        switch connection.kind {
        case .s3:
            return S3FileSystem(endpoint: valid.endpoint, region: connection.region ?? "us-east-1",
                                credentials: .init(accessKey: connection.user, secretKey: valid.secret))
        case .sftp:
            return SFTPFileSystem(host: connection.host, port: connection.port, user: connection.user,
                                  login: connection.useKey ? .key(path: connection.keyPath ?? "", passphrase: valid.secret) : .password(valid.secret),
                                  knownHosts: Connections.knownHostsFile,
                                  workFolder: URL(fileURLWithPath: "/tmp/pane-ssh-\(getuid())", isDirectory: true))
        case .ftp, .ftps:
            return FTPFileSystem(host: connection.host, port: connection.port, user: connection.user, password: valid.secret, secure: connection.kind == .ftps)
        }
    }
    /// A server Pane has not seen. The sheet asks "Trust this server?" with this fingerprint.
    struct PendingTrust: Equatable {
        let host: String
        let fingerprint: String
        let keyLine: String
    }
    private(set) var pendingTrust: PendingTrust?
    private var resumeAfterTrust: (() -> Void)?
    private var trustServer: (any RemoteFileSystem)?

    /// Called with a server that is connected and listed, and the place to show.
    var didConnect: (any RemoteFileSystem, URL) -> Void = { _, _ in }

    func openConnectSheet() {
        connectError = nil
        pendingTrust = nil
        prefill = nil
        editingID = nil
        showConnectSheet = true
    }

    func clearConnectError() { connectError = nil; pendingTrust = nil }

    /// The error from the last attempt, once. For a caller that shows it somewhere other than the sheet.
    func takeConnectError() -> String? {
        defer { connectError = nil }
        return connectError
    }

    func closeConnectSheet() {
        showConnectSheet = false
        pendingTrust = nil
        connectError = nil
    }

    /// For snapshots: fills the recent list without connecting.
    func recentServersForSnapshot(_ servers: [String]) {
        for server in servers.reversed() { recentServers.add(server) }
    }

    /// For snapshots: shows the "Trust this server?" question without connecting.
    func showTrustForSnapshot(host: String, fingerprint: String) {
        pendingTrust = PendingTrust(host: host, fingerprint: fingerprint, keyLine: "")
    }

    func clearRecentServers() {
        recentServers.clear()
        Prefs.defaults.set(recentServers.items, forKey: "pane.recentServers")
    }

    /// Connect: check the address, mount the share, then show it. A failure keeps the sheet open and says why.
    func connect(address text: String, user: String, password: String, remember: Bool) {
        guard !isConnecting else { return }
        let address: SMBAddress
        switch SMBAddress.parse(text) {
        case .success(let parsed): address = parsed
        case .failure(.empty): connectError = "Type a server address, like smb://nas/photos."; return
        case .failure(.notSMB): connectError = "The address has to start with smb://."; return
        case .failure(.noHost): connectError = "Add the server name after smb://."; return
        }
        connectError = nil
        isConnecting = true
        let account = user.isEmpty ? (address.user ?? "") : user
        Task {
            // A password saved earlier is used when the field is left empty.
            let secret = password.isEmpty && !account.isEmpty ? savedPassword(address.host, account) ?? "" : password
            let result = await mounter(address, account, secret)
            isConnecting = false
            switch result {
            case .success(let mountpoint):
                recentServers.add(address.displayText)
                Prefs.defaults.set(recentServers.items, forKey: "pane.recentServers")
                if remember, !account.isEmpty, !secret.isEmpty { savePassword(secret, address.host, account) }
                showConnectSheet = false
                didMount(mountpoint)
            case .failure(let failure):
                connectError = ConnectionError.message(forCode: failure.code)
            }
        }
    }

    /// Connect to an FTP, SFTP, or S3 server: check the form, sign in, then show the server's first folder.
    /// A server not seen before (SFTP) asks "Trust this server?" first. A changed key stops with a warning.
    func connect(_ form: ConnectionForm, remember: Bool, save: Bool = false, savedID: UUID? = nil) {
        guard !isConnecting else { return }
        let valid: ConnectionForm.Valid
        switch form.validated(store: secrets) {
        case .success(let checked): valid = checked
        case .failure(let error): connectError = error.message; return
        }
        connectError = nil
        pendingTrust = nil
        let connection = valid.connection
        let server = makeServer(valid)
        isConnecting = true
        let attempt: () -> Void = { [unowned self] in
            Task {
                defer { isConnecting = false; afterAttempt?() }
                do {
                    let start = try await server.start()
                    if remember, !valid.secret.isEmpty { secrets.save(valid.secret, for: connection) }
                    if save { record(connection, replacing: savedID) }
                    showConnectSheet = false
                    didConnect(server, RemoteURL.make(scheme: connection.scheme, host: connection.host, port: connection.port, path: start))
                } catch RemoteError.unknownHostKey(let fingerprint, let keyLine) {
                    pendingTrust = PendingTrust(host: connection.host, fingerprint: fingerprint, keyLine: keyLine)
                    trustServer = server
                } catch let error as RemoteError {
                    connectError = error.message
                } catch {
                    connectError = "Unable to reach the server."
                }
            }
        }
        resumeAfterTrust = { [unowned self] in isConnecting = true; attempt() }
        attempt()
    }

    func connectS3(accessKey: String, secretKey: String, region: String, endpoint: String, remember: Bool, save: Bool = false, savedID: UUID? = nil) {
        var form = ConnectionForm(kind: .s3)
        form.user = accessKey; form.secret = secretKey; form.region = region; form.endpoint = endpoint
        connect(form, remember: remember, save: save, savedID: savedID)
    }

    func connectSFTP(host: String, port: String, user: String, useKey: Bool, keyPath: String, secret: String, remember: Bool,
                     save: Bool = false, savedID: UUID? = nil) {
        var form = ConnectionForm(kind: .sftp)
        form.host = host; form.port = port; form.user = user; form.useKey = useKey; form.keyPath = keyPath; form.secret = secret
        connect(form, remember: remember, save: save, savedID: savedID)
    }

    func connectFTP(host: String, port: String, user: String, password: String, protocol choice: FTPProtocol, remember: Bool,
                    save: Bool = false, savedID: UUID? = nil) {
        var form = ConnectionForm(kind: choice == .tls ? .ftps : .ftp)
        form.host = host; form.port = port; form.user = user; form.secret = password
        connect(form, remember: remember, save: save, savedID: savedID)
    }

    /// Trust this server: remember its key, then connect again.
    func trustPendingServer() {
        guard let pending = pendingTrust, let server = trustServer as? SFTPFileSystem else { return }
        do { try server.trust(keyLine: pending.keyLine) } catch { connectError = "Unable to remember this server."; return }
        pendingTrust = nil
        resumeAfterTrust?()
    }

    func declinePendingServer() {
        pendingTrust = nil
        trustServer = nil
        resumeAfterTrust = nil
    }
}
