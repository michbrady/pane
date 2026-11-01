import Foundation
import PaneKit

/// Saved connections: the list in Settings, opening one from the Navigation pane, editing, and removing.
/// A saved connection holds the settings. Its password or secret key stays in the Keychain.
extension Connections {
    /// Adds a connection, or updates the one for the same server and user. `replacing` is the entry being edited.
    func record(_ connection: SavedConnection, replacing id: UUID?) {
        saved.save(connection, replacing: id)
        persistSaved()
    }

    private func persistSaved() {
        Prefs.defaults.set(saved.data, forKey: "pane.savedConnections")
        savedChanged()
    }

    /// Remove deletes the entry and its Keychain item.
    func remove(_ id: UUID) {
        guard let removed = saved.remove(id) else { return }
        secrets.delete(for: removed)
        persistSaved()
    }

    func openManageSheet() {
        showConnectSheet = false
        showManageSheet = true
    }

    /// Opens the Connect to Server sheet filled in with a saved connection. Connecting updates that entry.
    func openEdit(_ connection: SavedConnection) {
        showManageSheet = false
        clearConnectError()
        kind = connection.kind == .s3 ? .s3 : connection.kind == .sftp ? .sftp : .ftp
        if connection.kind == .ftp { ftpProtocol = .plain } else if connection.kind == .ftps { ftpProtocol = .tls }
        prefill = connection
        editingID = connection.id
        showConnectSheet = true
    }

    /// A click on a saved server's row, by its address.
    func openSaved(serverKey: String) {
        guard let connection = saved.connection(forServerKey: serverKey) else { return }
        openSaved(connection)
    }

    /// A click on a saved server that is not connected: connect with the saved settings and the Keychain's secret.
    /// A failure is said once, with the server's name. A server not seen before opens the sheet to ask about trusting it.
    func openSaved(_ connection: SavedConnection) {
        guard !isConnecting else { return }
        unableToConnect = nil
        let finish: () -> Void = { [unowned self] in
            afterAttempt = nil
            if pendingTrust != nil {
                // The question lives in the sheet.
                kind = connection.kind == .s3 ? .s3 : connection.kind == .sftp ? .sftp : .ftp
                prefill = connection
                editingID = connection.id
                showConnectSheet = true
            } else if let reason = takeConnectError() {
                unableToConnect = (connection.displayName, reason)
            }
        }
        afterAttempt = finish
        switch connection.kind {
        case .s3:
            connectS3(accessKey: connection.user, secretKey: "", region: connection.region ?? "us-east-1",
                      endpoint: connection.host + (connection.port.map { ":\($0)" } ?? ""), remember: false, save: false)
        case .sftp:
            connectSFTP(host: connection.host, port: connection.port.map(String.init) ?? "", user: connection.user,
                        useKey: connection.useKey, keyPath: connection.keyPath ?? "", secret: "", remember: false)
        case .ftp, .ftps:
            connectFTP(host: connection.host, port: connection.port.map(String.init) ?? "", user: connection.user, password: "",
                       protocol: connection.kind == .ftps ? .tls : .plain, remember: false)
        }
        // A missing password or key stops before any attempt starts.
        if !isConnecting { finish() }
    }

    /// For snapshots: a saved list without connecting or touching the Keychain.
    func savedForSnapshot(_ items: [SavedConnection]) {
        saved = SavedConnections(items: items)
        savedChanged()
    }
}
