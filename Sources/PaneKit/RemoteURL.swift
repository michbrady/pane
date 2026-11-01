import Foundation

/// Remote places are URLs with a scheme: `sftp://host/folder`, `ftp://host/folder`, `s3://bucket/key`.
/// These helpers keep them tidy, and walk up their paths like `Breadcrumbs` does for local folders.
public enum RemoteURL {
    public static let schemes: Set<String> = ["ftp", "ftps", "sftp", "s3"]

    public static func isRemote(_ url: URL) -> Bool {
        url.scheme.map { schemes.contains($0.lowercased()) } ?? false
    }

    /// Builds `scheme://user@host:port/path`. The path is encoded, and an empty one becomes "/".
    public static func make(scheme: String, host: String, port: Int? = nil, user: String? = nil, path: String = "/") -> URL {
        var parts = URLComponents()
        parts.scheme = scheme.lowercased()
        parts.host = host
        parts.port = port
        parts.user = user
        parts.path = path.hasPrefix("/") ? path : "/" + path
        return parts.url ?? URL(string: "\(scheme)://\(host)/")!
    }

    /// One spelling per place: a lowercase scheme and host, no trailing slash, "." and ".." resolved.
    /// The same folder reached two ways compares equal.
    public static func canonical(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        var stack: [String] = []
        for piece in parts.path.split(separator: "/", omittingEmptySubsequences: true) {
            if piece == "." { continue }
            if piece == ".." { _ = stack.popLast(); continue }
            stack.append(String(piece))
        }
        parts.path = "/" + stack.joined(separator: "/")
        return parts.url ?? url
    }

    /// The folder above, or nil at the top of the server.
    public static func parent(of url: URL) -> URL? {
        let here = canonical(url)
        guard !pathComponents(here).isEmpty, var parts = URLComponents(url: here, resolvingAgainstBaseURL: false) else { return nil }
        var pieces = pathComponents(here)
        pieces.removeLast()
        parts.path = "/" + pieces.joined(separator: "/")
        return parts.url
    }

    /// The server's top, then each folder down to this one. For the breadcrumbs.
    public static func chain(for url: URL) -> [URL] {
        var result: [URL] = []
        var current: URL? = canonical(url)
        while let place = current {
            result.append(place)
            current = parent(of: place)
        }
        return result.reversed()
    }

    /// The last folder or file name, or the server's name at the top.
    public static func name(of url: URL) -> String {
        pathComponents(canonical(url)).last ?? url.host ?? url.absoluteString
    }

    /// `scheme://host:port` with no path: what identifies one connection.
    public static func serverKey(_ url: URL) -> String {
        let place = canonical(url)
        let port = place.port.map { ":\($0)" } ?? ""
        return "\(place.scheme ?? "")://\(place.host ?? "")\(port)"
    }

    /// What a person typed in the Address bar, if it is a remote address. No path means the top.
    public static func parse(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.range(of: "://"), schemes.contains(trimmed[..<colon.lowerBound].lowercased()) else { return nil }
        let rest = trimmed[colon.upperBound...]
        guard let host = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first, !host.isEmpty else { return nil }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed.union(CharacterSet(charactersIn: ":/%@")))
        guard let url = URL(string: encoded ?? trimmed), url.host != nil else { return nil }
        return canonical(url)
    }

    public static func pathComponents(_ url: URL) -> [String] {
        url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
