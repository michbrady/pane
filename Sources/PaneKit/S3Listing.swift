import Foundation

/// Reads S3's XML answers: ListObjectsV2 (a folder's contents) and ListBuckets (the top).
public enum S3Listing {
    public struct Page: Equatable, Sendable {
        public var folders: [String] = []
        public var files: [File] = []
        public var nextToken: String?
    }

    public struct File: Equatable, Sendable {
        public let key: String
        public let size: Int64
        public let modified: Date?
    }

    public struct Bucket: Equatable, Sendable {
        public let name: String
        public let created: Date?
    }

    /// One page of ListObjectsV2. `nextToken` is set while `IsTruncated` is true.
    public static func parsePage(_ data: Data) -> Page? {
        let reader = Reader(collecting: ["Prefix", "Key", "Size", "LastModified", "NextContinuationToken", "IsTruncated"], groups: ["CommonPrefixes", "Contents"])
        guard reader.run(data) else { return nil }
        var page = Page()
        var truncated = false
        for group in reader.records {
            switch group.name {
            case "CommonPrefixes": if let prefix = group.values["Prefix"] { page.folders.append(prefix) }
            case "Contents":
                guard let key = group.values["Key"] else { continue }
                page.files.append(File(key: key, size: Int64(group.values["Size"] ?? "") ?? 0, modified: date(group.values["LastModified"])))
            default: break
            }
        }
        truncated = reader.top["IsTruncated"] == "true"
        if truncated { page.nextToken = reader.top["NextContinuationToken"] }
        return page
    }

    public static func parseBuckets(_ data: Data) -> [Bucket]? {
        let reader = Reader(collecting: ["Name", "CreationDate"], groups: ["Bucket"])
        guard reader.run(data) else { return nil }
        return reader.records.compactMap { group in
            group.values["Name"].map { Bucket(name: $0, created: date(group.values["CreationDate"])) }
        }
    }

    /// The `<Code>` and `<Message>` of an error answer.
    public static func parseError(_ data: Data) -> (code: String, message: String)? {
        let reader = Reader(collecting: ["Code", "Message"], groups: [])
        guard reader.run(data), let code = reader.top["Code"] else { return nil }
        return (code, reader.top["Message"] ?? "")
    }

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let plain = ISO8601DateFormatter()
        let fractions = ISO8601DateFormatter()
        fractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractions.date(from: text) ?? plain.date(from: text)
    }

    /// Collects the text of chosen tags. Tags inside a named group go to that group's record, the rest to `top`.
    private final class Reader: NSObject, XMLParserDelegate {
        struct Record { let name: String; var values: [String: String] = [:] }
        let wanted: Set<String>
        let groupNames: Set<String>
        var records: [Record] = []
        var top: [String: String] = [:]
        private var current: Record?
        private var text = ""

        init(collecting: Set<String>, groups: Set<String>) {
            wanted = collecting
            groupNames = groups
        }

        func run(_ data: Data) -> Bool {
            let parser = XMLParser(data: data)
            parser.delegate = self
            return parser.parse()
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            text = ""
            if groupNames.contains(name) { current = Record(name: name) }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if groupNames.contains(name), let done = current {
                records.append(done)
                current = nil
            } else if wanted.contains(name) {
                if current != nil { current?.values[name] = text } else { top[name] = text }
            }
        }
    }
}
