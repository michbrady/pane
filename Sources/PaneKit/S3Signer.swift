import CryptoKit
import Foundation

/// AWS Signature Version 4 for S3. Pure: give it a request and a date, get the headers to send.
public enum S3Signer {
    public struct Credentials: Sendable, Equatable {
        public let accessKey: String
        public let secretKey: String
        public init(accessKey: String, secretKey: String) {
            self.accessKey = accessKey
            self.secretKey = secretKey
        }
    }

    /// Characters S3 leaves as they are. Everything else is percent-encoded, "/" only when asked.
    private static func encode(_ text: String, slash: Bool) -> String {
        var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        if !slash { allowed.insert("/") }
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    public static func hex(_ data: some Sequence<UInt8>) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(_ data: Data) -> String { hex(SHA256.hash(data: data)) }

    private static func hmac(_ key: Data, _ message: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key)))
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    /// The headers to add: `x-amz-date`, `x-amz-content-sha256`, and `Authorization`.
    /// `headers` are the ones the caller sets itself (like Range). They are signed too.
    public static func sign(method: String, url: URL, headers: [String: String] = [:], payload: Data = Data(),
                            credentials: Credentials, region: String, date: Date, service: String = "s3",
                            payloadHash fixedHash: String? = nil) -> [String: String] {
        let amzDate = stamp(date)
        let day = String(amzDate.prefix(8))
        // A file sent from disk is not read twice just to hash it: the caller passes "UNSIGNED-PAYLOAD".
        let payloadHash = fixedHash ?? sha256(payload)

        var signed = headers.reduce(into: [String: String]()) { $0[$1.key.lowercased()] = $1.value.trimmingCharacters(in: .whitespaces) }
        let port = url.port.map { ":\($0)" } ?? ""
        signed["host"] = (url.host ?? "") + port
        signed["x-amz-date"] = amzDate
        signed["x-amz-content-sha256"] = payloadHash

        let names = signed.keys.sorted()
        let canonicalHeaders = names.map { "\($0):\(signed[$0]!)\n" }.joined()
        let signedNames = names.joined(separator: ";")

        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = (parts?.percentEncodedPath.removingPercentEncoding ?? url.path)
        var pairs: [String] = []
        for item in parts?.queryItems ?? [] {
            let name = encode(item.name, slash: true)
            let value = encode(item.value ?? "", slash: true)
            pairs.append(name + "=" + value)
        }
        // Sorting "name=value" strings orders by name first for S3's query names.
        let query = pairs.sorted().joined(separator: "&")

        let uri = encode(path.isEmpty ? "/" : path, slash: false)
        let lines: [String] = [method, uri, query, canonicalHeaders, signedNames, payloadHash]
        let canonical = lines.joined(separator: "\n")
        let scope = "\(day)/\(region)/\(service)/aws4_request"
        let toSign = ["AWS4-HMAC-SHA256", amzDate, scope, sha256(Data(canonical.utf8))].joined(separator: "\n")

        let dateKey = hmac(Data("AWS4\(credentials.secretKey)".utf8), day)
        let signingKey = hmac(hmac(hmac(dateKey, region), service), "aws4_request")
        let signature = hex(hmac(signingKey, toSign))

        return [
            "x-amz-date": amzDate,
            "x-amz-content-sha256": payloadHash,
            "Authorization": "AWS4-HMAC-SHA256 Credential=\(credentials.accessKey)/\(scope), SignedHeaders=\(signedNames), Signature=\(signature)",
        ]
    }
}
