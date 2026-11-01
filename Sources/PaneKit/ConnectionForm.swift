import Foundation

/// Where passwords and secret keys live. The app's adapter is the Keychain. Tests use `InMemorySecretStore`.
/// A secret is found again by the connection's server, user name, and protocol.
public protocol SecretStore: AnyObject {
    func save(_ secret: String, for connection: SavedConnection)
    func secret(for connection: SavedConnection) -> String?
    func delete(for connection: SavedConnection)
}

/// A secret store in memory, for tests and snapshots, that keeps a log of what was asked of it.
public final class InMemorySecretStore: SecretStore {
    public private(set) var values: [String: String] = [:]
    /// Keys saved, in order, like "sftp://nas.local/me".
    public private(set) var savedKeys: [String] = []
    public private(set) var deletedKeys: [String] = []

    public init() {}

    public static func key(for connection: SavedConnection) -> String { connection.serverKey + "/" + connection.user }

    /// A secret that is already there, as if saved earlier. Not logged as a save.
    public func preload(_ secret: String, forKey key: String) { values[key] = secret }

    public func save(_ secret: String, for connection: SavedConnection) {
        values[Self.key(for: connection)] = secret
        savedKeys.append(Self.key(for: connection))
    }

    public func secret(for connection: SavedConnection) -> String? { values[Self.key(for: connection)] }

    public func delete(for connection: SavedConnection) {
        values[Self.key(for: connection)] = nil
        deletedKeys.append(Self.key(for: connection))
    }
}

/// What the Connect to Server sheet holds for an FTP, SFTP, or S3 connection, before it is checked.
public struct ConnectionForm: Equatable, Sendable {
    public var kind: SavedConnection.Kind
    public var host = ""
    public var port = ""
    /// The user name. For S3, the access key.
    public var user = ""
    /// The typed password or secret key. Empty means use the one in the Keychain.
    public var secret = ""
    public var region = ""
    /// S3 only: empty means AWS in the chosen region.
    public var endpoint = ""
    public var useKey = false
    public var keyPath = ""

    public init(kind: SavedConnection.Kind) { self.kind = kind }

    public struct Valid: Equatable, Sendable {
        /// The settings to connect with, and to save.
        public let connection: SavedConnection
        /// The password, passphrase, or secret key. Empty only for an SFTP key with no passphrase.
        public let secret: String
        /// "host" or "host:port", as S3 wants its endpoint.
        public var endpoint: String { connection.host + (connection.port.map { ":\($0)" } ?? "") }
    }

    public struct FormError: Error, Equatable, Sendable {
        public let message: String
    }

    /// Checks the fields in the order they appear, and says what is missing in the words the sheet shows.
    public func validated(store: SecretStore) -> Result<Valid, FormError> {
        func fail(_ text: String) -> Result<Valid, FormError> { .failure(FormError(message: text)) }
        let user = user.trimmingCharacters(in: .whitespaces)

        if kind == .s3 {
            let area = region.trimmingCharacters(in: .whitespaces).lowercased()
            guard !user.isEmpty else { return fail("Type the access key.") }
            guard !area.isEmpty else { return fail("Type the region, like us-east-1.") }
            var name = endpoint.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if name.isEmpty { name = "s3.\(area).amazonaws.com" }
            let pieces = name.split(separator: ":", maxSplits: 1).map(String.init)
            let connection = SavedConnection(kind: .s3, host: pieces[0], port: pieces.count > 1 ? Int(pieces[1]) : nil, user: user, region: area)
            let stored = secret.isEmpty ? store.secret(for: connection) ?? "" : secret
            guard !stored.isEmpty else { return fail("Type the secret key.") }
            return .success(Valid(connection: connection, secret: stored))
        }

        let name = host.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return fail(kind == .sftp ? "Type the server name, like nas.local." : "Type the server name, like ftp.example.com.") }
        var number: Int?
        let typedPort = port.trimmingCharacters(in: .whitespaces)
        if !typedPort.isEmpty {
            guard let parsed = Int(typedPort), (1...65535).contains(parsed) else { return fail("The port is a number from 1 to 65535.") }
            number = parsed
        }
        guard !user.isEmpty else { return fail("Type the user name.") }
        let signsInWithKey = kind == .sftp && useKey
        guard !signsInWithKey || !keyPath.isEmpty else { return fail("Choose a key file.") }
        let connection = SavedConnection(kind: kind, host: name, port: number, user: user, useKey: signsInWithKey, keyPath: signsInWithKey ? keyPath : nil)
        let stored = secret.isEmpty ? store.secret(for: connection) ?? "" : secret
        guard signsInWithKey || !stored.isEmpty else { return fail("Type the password.") }
        return .success(Valid(connection: connection, secret: stored))
    }
}
