import Foundation

/// Sends one signed request. The real one is URLSession. Tests give a stub.
public protocol S3Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: S3Transport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw RemoteError.connectionLost }
            return (data, http)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost].contains(error.code) {
            throw RemoteError.connectionLost
        }
    }
}

/// An S3 account as a file system. `s3://host/bucket/key`: the host is the endpoint, the top lists
/// buckets, and keys with "/" in them are folders. Browsing only. Changing files comes in S-065.
public final class S3FileSystem: RemoteFileSystem, @unchecked Sendable {
    public let serverKey: String
    private let host: String
    private let port: Int?
    private let region: String
    private let credentials: S3Signer.Credentials
    private let transport: S3Transport
    private let now: @Sendable () -> Date
    private let secure: Bool

    /// `endpoint` is a host like "s3.us-east-1.amazonaws.com" or "minio.local:9000".
    public init(endpoint: String, region: String, credentials: S3Signer.Credentials, secure: Bool = true,
                transport: S3Transport = URLSessionTransport(), now: @escaping @Sendable () -> Date = { Date() }) {
        let pieces = endpoint.split(separator: ":", maxSplits: 1)
        host = String(pieces.first ?? "").lowercased()
        port = pieces.count > 1 ? Int(pieces[1]) : nil
        self.region = region
        self.credentials = credentials
        self.secure = secure
        self.transport = transport
        self.now = now
        serverKey = "s3://" + host + (port.map { ":\($0)" } ?? "")
    }

    public func reconnect() async throws { _ = try await buckets() }
    public func disconnect() async {}

    public func exists(_ url: URL) async -> Bool {
        (try? await list(url)) != nil
    }

    public func list(_ folder: URL) async throws -> [FolderItem] {
        let pieces = RemoteURL.pathComponents(RemoteURL.canonical(folder))
        guard let bucket = pieces.first else {
            return try await buckets().map {
                FolderItem(url: child(folder, [$0.name]), name: $0.name, isFolder: true, size: nil, modified: $0.created, kind: "Bucket")
            }
        }
        let prefix = pieces.dropFirst().map { $0 + "/" }.joined()
        var items: [FolderItem] = []
        var token: String?
        repeat {
            let page = try await listPage(bucket: bucket, prefix: prefix, token: token)
            for folderPrefix in page.folders {
                let name = String(folderPrefix.dropFirst(prefix.count).dropLast())
                guard !name.isEmpty else { continue }
                items.append(FolderItem(url: child(folder, pieces + [name]), name: name, isFolder: true, size: nil, modified: nil,
                                        kind: FolderItem.kind(forFileNamed: name, isFolder: true)))
            }
            for file in page.files {
                let name = String(file.key.dropFirst(prefix.count))
                // The key that is the folder itself ("docs/") is not an item in it.
                guard !name.isEmpty, !name.hasSuffix("/") else { continue }
                items.append(FolderItem(url: child(folder, pieces + [name]), name: name, isFolder: false, size: file.size, modified: file.modified,
                                        kind: FolderItem.kind(forFileNamed: name, isFolder: false)))
            }
            token = page.nextToken
        } while token != nil
        return items
    }

    public func copy(_ source: URL, to destination: URL) async throws { throw RemoteError.other("not supported") }
    public func move(_ source: URL, to destination: URL) async throws { throw RemoteError.other("not supported") }
    public func trash(_ url: URL) async throws -> URL? { throw RemoteError.other("not supported") }
    public func remove(_ url: URL) async throws { throw RemoteError.other("not supported") }
    public func makeFolder(_ url: URL) async throws { throw RemoteError.other("not supported") }

    // MARK: Requests

    private func child(_ like: URL, _ components: [String]) -> URL {
        RemoteURL.make(scheme: "s3", host: host, port: port, user: nil, path: "/" + components.joined(separator: "/"))
    }

    private func buckets() async throws -> [S3Listing.Bucket] {
        let data = try await get(path: "/", query: [])
        guard let result = S3Listing.parseBuckets(data) else { throw RemoteError.other("Unable to read the server's answer.") }
        return result
    }

    private func listPage(bucket: String, prefix: String, token: String?) async throws -> S3Listing.Page {
        var query = [URLQueryItem(name: "list-type", value: "2"), URLQueryItem(name: "delimiter", value: "/")]
        if !prefix.isEmpty { query.append(URLQueryItem(name: "prefix", value: prefix)) }
        if let token { query.append(URLQueryItem(name: "continuation-token", value: token)) }
        let data = try await get(path: "/" + bucket, query: query)
        guard let page = S3Listing.parsePage(data) else { throw RemoteError.other("Unable to read the server's answer.") }
        return page
    }

    /// Path-style addressing (`host/bucket/key`) works for AWS and for MinIO, R2, and the rest.
    private func get(path: String, query: [URLQueryItem]) async throws -> Data {
        var parts = URLComponents()
        parts.scheme = secure ? "https" : "http"
        parts.host = host
        parts.port = port
        parts.percentEncodedPath = path.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        parts.queryItems = query.isEmpty ? nil : query
        // URLComponents leaves "+" and "&" in values; S3 wants them encoded.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        if let items = parts.queryItems {
            parts.percentEncodedQueryItems = items.map {
                URLQueryItem(name: $0.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.name,
                             value: $0.value?.addingPercentEncoding(withAllowedCharacters: allowed))
            }
        }
        guard let url = parts.url else { throw RemoteError.other("Unable to build that address.") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        for (name, value) in S3Signer.sign(method: "GET", url: url, credentials: credentials, region: region, date: now()) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw Self.error(status: response.statusCode, body: data) }
        return data
    }

    static func error(status: Int, body: Data) -> RemoteError {
        let answer = S3Listing.parseError(body)
        switch answer?.code {
        case "InvalidAccessKeyId", "SignatureDoesNotMatch", "AccessDenied", "ExpiredToken": return .denied("Access denied.")
        case "NoSuchBucket": return .other("That bucket does not exist.")
        case "AuthorizationHeaderMalformed", "PermanentRedirect": return .other("That region does not match the bucket. Check the Region.")
        default: break
        }
        if status == 401 || status == 403 { return .denied("Access denied.") }
        if status == 404 { return .other("That folder does not exist.") }
        return .other(answer?.message.isEmpty == false ? answer!.message : "The server answered with an error (\(status)).")
    }
}
