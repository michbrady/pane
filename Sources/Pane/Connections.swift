import Foundation
import Observation
import PaneKit

/// Connecting to servers: the Connect to Server sheet, the recent list, and the mount. SMB today.
/// FTP, SFTP, and S3 connections join here. A connected share appears under Network through `Places`.
@Observable
final class Connections {
    var showConnectSheet = false
    private(set) var isConnecting = false
    private(set) var connectError: String?
    private(set) var recentServers = RecentServers(Prefs.defaults.stringArray(forKey: "pane.recentServers") ?? [])
    /// The real mount and Keychain calls. Tests swap them, so they never reach a network or your Keychain.
    var mounter: (SMBAddress, String?, String?) async -> Result<URL, MountFailure> = { await SMBMount.mount($0, user: $1, password: $2) }
    var savePassword: (String, String, String) -> Void = { PasswordKeychain.save($0, server: $1, account: $2) }
    var savedPassword: (String, String) -> String? = { PasswordKeychain.password(server: $0, account: $1) }
    /// Called with where a new share appeared. AppModel refreshes the places and shows it.
    var didMount: (URL) -> Void = { _ in }

    func openConnectSheet() {
        connectError = nil
        showConnectSheet = true
    }

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
}
