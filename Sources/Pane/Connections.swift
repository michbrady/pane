import Foundation
import Observation
import PaneKit

/// Connecting to servers: the Connect to Server sheet, the recent list, and the mount. SMB today.
/// FTP, SFTP, and S3 connections join here. A connected share appears under Network through `Places`.
@Observable
final class Connections {
    var showConnectSheet = false

    /// What the sheet connects to. More join as they are built.
    enum Kind: String, CaseIterable, Identifiable {
        case share = "File Share (SMB)", s3 = "Amazon S3"
        var id: String { rawValue }
    }
    var kind = Kind.share
    private(set) var isConnecting = false
    private(set) var connectError: String?
    private(set) var recentServers = RecentServers(Prefs.defaults.stringArray(forKey: "pane.recentServers") ?? [])
    /// The real mount and Keychain calls. Tests swap them, so they never reach a network or your Keychain.
    var mounter: (SMBAddress, String?, String?) async -> Result<URL, MountFailure> = { await SMBMount.mount($0, user: $1, password: $2) }
    var savePassword: (String, String, String) -> Void = { PasswordKeychain.save($0, server: $1, account: $2) }
    var savedPassword: (String, String) -> String? = { PasswordKeychain.password(server: $0, account: $1) }
    /// Called with where a new share appeared. AppModel refreshes the places and shows it.
    var didMount: (URL) -> Void = { _ in }
    /// Builds the S3 file system. Tests give one that talks to a stub, never the network.
    var makeS3: (String, String, S3Signer.Credentials) -> S3FileSystem = { endpoint, region, credentials in
        S3FileSystem(endpoint: endpoint, region: region, credentials: credentials)
    }
    var saveSecret: (String, String, String) -> Void = { PasswordKeychain.save($0, server: $1, account: $2, proto: kSecAttrProtocolHTTPS) }
    var savedSecret: (String, String) -> String? = { PasswordKeychain.password(server: $0, account: $1, proto: kSecAttrProtocolHTTPS) }
    /// Called with a server that is connected and listed, and the place to show.
    var didConnect: (any RemoteFileSystem, URL) -> Void = { _, _ in }

    func openConnectSheet() {
        connectError = nil
        showConnectSheet = true
    }

    func clearConnectError() { connectError = nil }

    func closeConnectSheet() {
        showConnectSheet = false
        connectError = nil
    }

    /// For snapshots: fills the recent list without connecting.
    func recentServersForSnapshot(_ servers: [String]) {
        for server in servers.reversed() { recentServers.add(server) }
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

    /// Connect to S3: list the account's buckets to prove the keys work, then show them as folders.
    /// An empty Endpoint means AWS in the chosen Region. A saved secret is used when the field is left empty.
    func connectS3(accessKey: String, secretKey: String, region: String, endpoint: String, remember: Bool) {
        guard !isConnecting else { return }
        let key = accessKey.trimmingCharacters(in: .whitespaces)
        let area = region.trimmingCharacters(in: .whitespaces).lowercased()
        let host = endpoint.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !key.isEmpty else { connectError = "Type the access key."; return }
        guard !area.isEmpty else { connectError = "Type the region, like us-east-1."; return }
        let endpointHost = host.isEmpty ? "s3.\(area).amazonaws.com" : host
        let secret = secretKey.isEmpty ? savedSecret(endpointHost, key) ?? "" : secretKey
        guard !secret.isEmpty else { connectError = "Type the secret key."; return }
        connectError = nil
        isConnecting = true
        let server = makeS3(endpointHost, area, .init(accessKey: key, secretKey: secret))
        Task {
            defer { isConnecting = false }
            do {
                let top = RemoteURL.make(scheme: "s3", host: endpointHost.split(separator: ":").first.map(String.init) ?? endpointHost,
                                         port: endpointHost.split(separator: ":").dropFirst().first.flatMap { Int($0) })
                _ = try await server.list(top)
                if remember { saveSecret(secret, endpointHost, key) }
                showConnectSheet = false
                didConnect(server, top)
            } catch let error as RemoteError {
                connectError = Self.words(error)
            } catch {
                connectError = "Unable to reach the server."
            }
        }
    }

    static func words(_ error: RemoteError) -> String {
        switch error {
        case .denied(let reason), .other(let reason): reason
        case .connectionLost, .notConnected: "Unable to reach the server."
        }
    }
}
