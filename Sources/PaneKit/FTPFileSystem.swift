import Foundation

/// The text side of FTP: reading a directory listing, and the words for what curl says when it fails.
public enum FTPText {
    /// A LIST answer as items. Reads the Unix format (`drwxr-xr-x 2 user group 4096 Oct 31 12:00 name`)
    /// and the Windows IIS format (`10-31-26  09:15AM  <DIR>  name`). Other lines are skipped.
    public static func parseListing(_ output: String, folder: URL, now: Date = Date()) -> [FolderItem] {
        var items = SFTPText.parseListing(output, folder: folder, now: now)
        let seen = Set(items.map(\.name))
        let pattern = #"^(\d{2})-(\d{2})-(\d{2,4})\s+(\d{1,2}):(\d{2})\s*([AP]M)\s+(<DIR>|\d+)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return items }
        let calendar = Calendar(identifier: .gregorian)
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
            func text(_ index: Int) -> String { Range(match.range(at: index), in: line).map { String(line[$0]) } ?? "" }
            let name = text(8).trimmingCharacters(in: .whitespaces)
            guard name != ".", name != "..", !seen.contains(name) else { continue }
            let isFolder = text(7) == "<DIR>"
            var year = Int(text(3)) ?? 0
            if year < 100 { year += year < 70 ? 2000 : 1900 }
            var hour = (Int(text(4)) ?? 0) % 12
            if text(6) == "PM" { hour += 12 }
            let modified = calendar.date(from: DateComponents(year: year, month: Int(text(1)), day: Int(text(2)), hour: hour, minute: Int(text(5))))
            items.append(FolderItem(url: RemoteURL.child(of: folder, named: name), name: name, isFolder: isFolder,
                                    size: isFolder ? nil : Int64(text(7)), modified: modified,
                                    kind: FolderItem.kind(forFileNamed: name, isFolder: isFolder)))
        }
        return items
    }

    /// curl's exit code and message, as an error with words a person can act on.
    public static func classify(status: Int32, stderr: String) -> RemoteError {
        switch status {
        case 67: return .denied("Access denied.")
        case 9 where stderr.contains("530"): return .denied("Access denied.")
        case 9, 78, 19: return .other("That folder does not exist.")
        case 6, 7, 28, 52, 55, 56: return .connectionLost
        case 64: return .other("This server does not support TLS. Choose FTP, which sends your password without encryption.")
        case 35, 58, 59, 60, 77, 83: return .other("Unable to verify this server's certificate.")
        default:
            let line = stderr.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return .other(line.isEmpty ? "The server answered with an error." : line)
        }
    }

    /// A value inside double quotes in a curl config file.
    static func configQuote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// An FTP or FTPS server reached with the system `curl`: passive mode, explicit TLS for `ftps`, UTF-8 names.
/// Paths are relative to the folder the server signs you in to. Browsing only until S-065.
public final class FTPFileSystem: RemoteFileSystem, @unchecked Sendable {
    public let serverKey: String
    private let scheme: String
    private let host: String
    private let port: Int?
    private let user: String
    private let password: String
    private let runner: ProcessRunner
    private let now: @Sendable () -> Date

    /// `secure` asks for TLS before the password is sent, and stops if the server will not.
    public init(host: String, port: Int? = nil, user: String, password: String, secure: Bool,
                runner: ProcessRunner = SystemProcessRunner(), now: @escaping @Sendable () -> Date = { Date() }) {
        scheme = secure ? "ftps" : "ftp"
        self.host = host.lowercased()
        self.port = port
        self.user = user
        self.password = password
        self.runner = runner
        self.now = now
        serverKey = "\(scheme)://" + self.host + (port.map { ":\($0)" } ?? "")
    }

    /// Signs in by listing the starting folder. Returns where the person starts: the top.
    public func start() async throws -> String {
        _ = try await fetch("/")
        return "/"
    }

    public func reconnect() async throws { _ = try await start() }
    public func disconnect() async {}

    public func exists(_ url: URL) async -> Bool { (try? await list(url)) != nil }

    public func list(_ folder: URL) async throws -> [FolderItem] {
        let output = try await fetch(RemoteURL.canonical(folder).path)
        return FTPText.parseListing(output, folder: folder, now: now())
    }

    public func copy(_ source: URL, to destination: URL) async throws { throw RemoteError.other("not supported") }
    public func move(_ source: URL, to destination: URL) async throws { throw RemoteError.other("not supported") }
    public func trash(_ url: URL) async throws -> URL? { throw RemoteError.other("not supported") }
    public func remove(_ url: URL) async throws { throw RemoteError.other("not supported") }
    public func makeFolder(_ url: URL) async throws { throw RemoteError.other("not supported") }

    /// The address and the login go in on stdin as a curl config, so the password never shows in `ps`.
    private func fetch(_ path: String) async throws -> String {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        parts.port = port
        parts.path = path.hasSuffix("/") ? path : path + "/"   // a trailing slash asks for the folder's listing
        guard let address = parts.string else { throw RemoteError.other("Unable to build that address.") }
        let config = "url = \(FTPText.configQuote(address))\nuser = \(FTPText.configQuote(user + ":" + password))\n"
        var arguments = ["--silent", "--show-error", "--connect-timeout", "15", "--max-time", "60", "--config", "-"]
        if scheme == "ftps" { arguments.append("--ssl-reqd") }
        let result = try await runner.run("/usr/bin/curl", arguments, input: config, environment: [:])
        guard result.status == 0 else { throw FTPText.classify(status: result.status, stderr: result.stderr) }
        return result.stdout
    }
}
