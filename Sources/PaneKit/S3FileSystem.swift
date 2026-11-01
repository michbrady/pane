import Foundation

/// Sends one signed request. The real one is URLSession. Tests give a stub.
public protocol S3Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Sends a file as the request's body, without loading it into memory.
    func upload(_ request: URLRequest, fromFile: URL, progress: @escaping ByteProgress) async throws -> (Data, HTTPURLResponse)
    /// Saves the answer's body to `file`, without loading it into memory.
    func download(_ request: URLRequest, to file: URL, progress: @escaping ByteProgress) async throws -> HTTPURLResponse
}

public extension S3Transport {
    func upload(_ request: URLRequest, fromFile: URL, progress: @escaping ByteProgress) async throws -> (Data, HTTPURLResponse) {
        throw RemoteError.other("not supported")
    }
    func download(_ request: URLRequest, to file: URL, progress: @escaping ByteProgress) async throws -> HTTPURLResponse {
        throw RemoteError.other("not supported")
    }
}

/// Reports how far a transfer has got.
private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: ByteProgress
    init(_ progress: @escaping ByteProgress) { self.progress = progress }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        progress(totalBytesSent)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
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

    public func upload(_ request: URLRequest, fromFile: URL, progress: @escaping ByteProgress) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fromFile, delegate: ProgressDelegate(progress))
            guard let http = response as? HTTPURLResponse else { throw RemoteError.connectionLost }
            return (data, http)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost].contains(error.code) {
            throw RemoteError.connectionLost
        }
    }

    public func download(_ request: URLRequest, to file: URL, progress: @escaping ByteProgress) async throws -> HTTPURLResponse {
        do {
            let (temporary, response) = try await URLSession.shared.download(for: request, delegate: ProgressDelegate(progress))
            guard let http = response as? HTTPURLResponse else { throw RemoteError.connectionLost }
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: temporary, to: file)
            return http
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
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

    public func exists(_ url: URL) async -> Bool { await RemoteTree.exists(url, in: self) }

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
    /// S3 has no rename: copy to the new key, then delete the old one. A folder goes key by key.
    public func move(_ source: URL, to destination: URL) async throws {
        let from = RemoteURL.pathComponents(RemoteURL.canonical(source)), to = RemoteURL.pathComponents(RemoteURL.canonical(destination))
        guard from.count >= 2, to.count >= 2 else { throw RemoteError.other("Buckets cannot be renamed here. Do that in the S3 console.") }
        let sourceKey = "/" + from.joined(separator: "/")
        let children = try await list(source)
        if children.isEmpty {
            do { try await copyKey(from: sourceKey, to: "/" + to.joined(separator: "/")) } catch {
                // No such file: an empty folder is just its "folder/" key.
                try await makeFolder(destination)
                _ = try await send("DELETE", path: sourceKey + "/")
                return
            }
            _ = try await send("DELETE", path: sourceKey)
        } else {
            for child in children { try await move(child.url, to: RemoteURL.child(of: destination, named: RemoteURL.name(of: child.url))) }
            try await makeFolder(destination)
            _ = try await send("DELETE", path: sourceKey + "/")
        }
    }

    private func copyKey(from source: String, to destination: String) async throws {
        let encoded = source.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? String($0) }
            .joined(separator: "/")
        let request = try signedRequest("PUT", path: destination, query: [], payloadHash: nil, headers: ["x-amz-copy-source": encoded])
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw Self.error(status: response.statusCode, body: data) }
        // S3 can answer 200 and still say it failed.
        if S3Listing.parseError(data) != nil { throw Self.error(status: 500, body: data) }
    }
    public func trash(_ url: URL) async throws -> URL? { throw RemoteError.other("not supported") }

    /// A folder is a key ending in "/". Buckets are made in the S3 console, not here.
    public func makeFolder(_ url: URL) async throws {
        let pieces = RemoteURL.pathComponents(RemoteURL.canonical(url))
        guard pieces.count >= 2 else { throw RemoteError.other("Create buckets in the S3 console. Pane can make folders inside one.") }
        _ = try await send("PUT", path: "/" + pieces.joined(separator: "/") + "/")
    }

    /// Deletes a file, or a folder and everything under it. Deleting a key that is not there is not an error in S3.
    public func remove(_ url: URL) async throws {
        let pieces = RemoteURL.pathComponents(RemoteURL.canonical(url))
        guard pieces.count >= 2 else { throw RemoteError.other("Pane does not delete buckets. Do that in the S3 console.") }
        for child in try await list(url) { try await remove(child.url) }
        let key = "/" + pieces.joined(separator: "/")
        _ = try await send("DELETE", path: key)
        _ = try await send("DELETE", path: key + "/")
    }

    public func download(_ remote: URL, to local: URL, progress: @escaping ByteProgress) async throws {
        let pieces = RemoteURL.pathComponents(RemoteURL.canonical(remote))
        guard pieces.count >= 2 else { throw RemoteError.other("That is not a file.") }
        let request = try signedRequest("GET", path: "/" + pieces.joined(separator: "/"), query: [], payloadHash: nil)
        let response = try await transport.download(request, to: local, progress: progress)
        guard (200..<300).contains(response.statusCode) else {
            try? FileManager.default.removeItem(at: local)
            throw Self.error(status: response.statusCode, body: Data())
        }
    }

    /// One PUT sends the whole file, and S3 shows the key only when it all arrived. A cancel leaves nothing.
    public func upload(_ local: URL, to remote: URL, replacing: Bool, progress: @escaping ByteProgress) async throws {
        let pieces = RemoteURL.pathComponents(RemoteURL.canonical(remote))
        guard pieces.count >= 2 else { throw RemoteError.other("Open a bucket first. Files go inside a bucket.") }
        let size = (try FileManager.default.attributesOfItem(atPath: local.path)[.size] as? Int64) ?? 0
        guard size <= 5_000_000_000 else { throw RemoteError.other("Files over 5 GB cannot be uploaded to S3 yet.") }
        let request = try signedRequest("PUT", path: "/" + pieces.joined(separator: "/"), query: [], payloadHash: "UNSIGNED-PAYLOAD")
        let (data, response) = try await transport.upload(request, fromFile: local, progress: progress)
        guard (200..<300).contains(response.statusCode) else { throw Self.error(status: response.statusCode, body: data) }
    }

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

    private func get(path: String, query: [URLQueryItem]) async throws -> Data {
        try await send("GET", path: path, query: query)
    }

    private func send(_ method: String, path: String, query: [URLQueryItem] = []) async throws -> Data {
        let request = try signedRequest(method, path: path, query: query, payloadHash: nil)
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw Self.error(status: response.statusCode, body: data) }
        return data
    }

    /// Path-style addressing (`host/bucket/key`) works for AWS and for MinIO, R2, and the rest.
    private func signedRequest(_ method: String, path: String, query: [URLQueryItem], payloadHash: String?, headers: [String: String] = [:]) throws -> URLRequest {
        var parts = URLComponents()
        parts.scheme = secure ? "https" : "http"
        parts.host = host
        parts.port = port
        parts.percentEncodedPath = path.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        // URLComponents leaves "+" and "&" in values; S3 wants them encoded.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        if !query.isEmpty {
            parts.percentEncodedQueryItems = query.map {
                URLQueryItem(name: $0.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.name,
                             value: $0.value?.addingPercentEncoding(withAllowedCharacters: allowed))
            }
        }
        guard let url = parts.url else { throw RemoteError.other("Unable to build that address.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = payloadHash == nil && method == "GET" ? 30 : 600
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let signed = S3Signer.sign(method: method, url: url, headers: headers, credentials: credentials, region: region, date: now(), payloadHash: payloadHash)
        for (name, value) in signed { request.setValue(value, forHTTPHeaderField: name) }
        return request
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
