import Foundation

/// A server or bucket the person saved. It holds the settings and nothing secret: the password or secret key
/// lives in the Keychain, found again by the host and the user name.
public struct SavedConnection: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case ftp, ftps, sftp, s3

        /// "SFTP", "FTP with TLS", "Amazon S3".
        public var title: String {
            switch self {
            case .ftp: "FTP"
            case .ftps: "FTP with TLS"
            case .sftp: "SFTP"
            case .s3: "Amazon S3"
            }
        }

        /// The SF Symbol for the row in the Navigation pane.
        public var symbol: String {
            switch self {
            case .ftp: "arrow.left.arrow.right"
            case .ftps: "lock"
            case .sftp: "terminal"
            case .s3: "shippingbox"
            }
        }
    }

    public let id: UUID
    public var kind: Kind
    /// The server's name. For S3, the endpoint, like "s3.us-east-1.amazonaws.com" or "minio.local".
    public var host: String
    public var port: Int?
    /// The user name. For S3, the access key.
    public var user: String
    /// S3 only.
    public var region: String?
    /// SFTP only: sign in with a key file instead of a password.
    public var useKey: Bool
    public var keyPath: String?

    public init(id: UUID = UUID(), kind: Kind, host: String, port: Int? = nil, user: String,
                region: String? = nil, useKey: Bool = false, keyPath: String? = nil) {
        self.id = id
        self.kind = kind
        self.host = host.lowercased()
        self.port = port
        self.user = user
        self.region = region
        self.useKey = useKey
        self.keyPath = keyPath
    }

    /// "sftp", "ftp", "ftps", or "s3".
    public var scheme: String { kind.rawValue }

    /// What the router files the open connection under, like "sftp://nas".
    public var serverKey: String {
        "\(scheme)://\(host)" + (port.map { ":\($0)" } ?? "")
    }

    /// "nas (SFTP)".
    public var displayName: String { "\(host) (\(kind == .ftps ? "FTPS" : kind == .s3 ? "S3" : kind.rawValue.uppercased()))" }

    /// "me@nas.local", or the access key for S3.
    public var detail: String { kind == .s3 ? "Access key \(user)" : "\(user)@\(host)" }

    /// The place to open: the top of the server.
    public var address: URL { RemoteURL.make(scheme: scheme, host: host, port: port) }

    /// Same server and same sign-in, so saving it again updates the entry instead of adding one.
    func matches(_ other: SavedConnection) -> Bool {
        kind == other.kind && host == other.host && port == other.port && user == other.user
    }
}

/// The list of saved connections, kept as one JSON blob in Settings.
public struct SavedConnections: Equatable, Sendable {
    public private(set) var items: [SavedConnection]

    public init(items: [SavedConnection] = []) { self.items = items }

    public init(data: Data?) {
        items = data.flatMap { try? JSONDecoder().decode([SavedConnection].self, from: $0) } ?? []
    }

    public var data: Data { (try? JSONEncoder().encode(items)) ?? Data() }

    /// Adds a connection, or updates the one for the same server and user. `replacing` is an entry being edited.
    public mutating func save(_ connection: SavedConnection, replacing id: UUID? = nil) {
        // Editing keeps the entry's id and its place in the list.
        if let id, let index = items.firstIndex(where: { $0.id == id }) {
            items[index] = SavedConnection(id: id, kind: connection.kind, host: connection.host, port: connection.port, user: connection.user,
                                           region: connection.region, useKey: connection.useKey, keyPath: connection.keyPath)
            return
        }
        if let index = items.firstIndex(where: { $0.matches(connection) }) {
            items[index] = SavedConnection(id: items[index].id, kind: connection.kind, host: connection.host, port: connection.port,
                                           user: connection.user, region: connection.region, useKey: connection.useKey, keyPath: connection.keyPath)
        } else {
            items.append(connection)
        }
    }

    @discardableResult
    public mutating func remove(_ id: UUID) -> SavedConnection? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    public func connection(forServerKey key: String) -> SavedConnection? { items.first { $0.serverKey == key } }
}
