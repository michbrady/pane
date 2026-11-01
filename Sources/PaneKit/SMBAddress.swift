import Foundation

/// What a person types in Connect to Server: `smb://nas/photos`.
public struct SMBAddress: Equatable, Sendable {
    public let host: String
    /// A name typed in the address, like `smb://me@nas/photos`.
    public let user: String?
    /// The share, then any folders inside it, as typed.
    public let path: [String]

    public enum Failure: Error, Equatable, Sendable {
        case empty
        /// The address does not start with smb://.
        case notSMB
        case noHost
    }

    /// The address as a URL, with spaces and special characters encoded.
    public var url: URL {
        var text = "smb://"
        if let user, !user.isEmpty { text += Self.encode(user) + "@" }
        text += host
        for part in path { text += "/" + Self.encode(part) }
        return URL(string: text) ?? URL(string: "smb://\(host)")!
    }

    /// Like "smb://nas/photos", for a list of recent servers.
    public var displayText: String {
        "smb://" + host + path.map { "/" + $0 }.joined()
    }

    public static func parse(_ text: String) -> Result<SMBAddress, Failure> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.lowercased().hasPrefix("smb://") else { return .failure(.notSMB) }
        let rest = String(trimmed.dropFirst("smb://".count))
        // A slash straight after smb:// means the server name is missing.
        guard !rest.hasPrefix("/") else { return .failure(.noHost) }
        var parts = rest.split(separator: "/", omittingEmptySubsequences: true).map { String($0).removingPercentEncoding ?? String($0) }
        guard var hostPart = parts.first, !hostPart.isEmpty else { return .failure(.noHost) }
        parts.removeFirst()
        var user: String?
        if let at = hostPart.lastIndex(of: "@") {
            user = String(hostPart[..<at])
            hostPart = String(hostPart[hostPart.index(after: at)...])
        }
        guard !hostPart.isEmpty else { return .failure(.noHost) }
        return .success(SMBAddress(host: hostPart, user: user, path: parts))
    }

    private static func encode(_ part: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/@:?#")
        return part.addingPercentEncoding(withAllowedCharacters: allowed) ?? part
    }
}

/// The servers connected to before, newest first.
public struct RecentServers: Equatable, Sendable {
    public private(set) var items: [String]
    public static let limit = 8

    public init(_ items: [String] = []) {
        self.items = items
    }

    /// A server already in the list moves to the top. The list keeps the last eight.
    public mutating func add(_ address: String) {
        items.removeAll { $0.caseInsensitiveCompare(address) == .orderedSame }
        items.insert(address, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }

    public mutating func clear() {
        items = []
    }
}

/// A connection that did not work, with the system's code.
public struct MountFailure: Error, Equatable, Sendable {
    public let code: Int32

    public init(code: Int32) {
        self.code = code
    }
}

/// Plain words for the codes the system gives back when a connection fails.
public enum ConnectionError {
    public static func message(forCode code: Int32) -> String {
        switch code {
        case 1, 13, 80: "The name or password was not accepted."
        case 2, 20: "The server answered, but it has no share with that name."
        case 17: "That share is already connected."
        case 60, 61, 64, 65: "The server did not answer. Check the address and your network."
        default: "Unable to connect (error \(code))."
        }
    }
}
