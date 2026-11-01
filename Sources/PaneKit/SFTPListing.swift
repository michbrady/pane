import Foundation

/// The text side of SFTP: what to send `sftp`, and how to read what it prints. Pure, so tests cover it.
public enum SFTPText {
    /// A path as `sftp` wants it in a batch: in double quotes, with backslash and quote escaped.
    public static func quote(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// One folder's `ls -ln` output as items. Lines that are not entries (the echoed command) are skipped.
    /// Times without a year are this year, or last year when that would be in the future.
    public static func parseListing(_ output: String, folder: URL, now: Date = Date()) -> [FolderItem] {
        let pattern = #"^([-dlbcps])[rwxsStT-]{9}[+@.]?\s+\d+\s+\S+\s+\S+\s+(\d+)\s+([A-Z][a-z]{2})\s+(\d{1,2})\s+(\d{1,2}:\d{2}|\d{4})\s(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let calendar = Calendar(identifier: .gregorian)
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        var items: [FolderItem] = []
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range) else { continue }
            func text(_ index: Int) -> String { Range(match.range(at: index), in: line).map { String(line[$0]) } ?? "" }
            var name = text(6)
            let isLink = text(1) == "l"
            if isLink, let arrow = name.range(of: " -> ") { name = String(name[..<arrow.lowerBound]) }
            guard name != ".", name != "..", !name.isEmpty else { continue }
            let isFolder = text(1) == "d"
            var parts = DateComponents(year: calendar.component(.year, from: now))
            parts.month = (months.firstIndex(of: text(3)) ?? 0) + 1
            parts.day = Int(text(4))
            let when = text(5)
            if when.contains(":") {
                let hm = when.split(separator: ":").compactMap { Int($0) }
                parts.hour = hm.first
                parts.minute = hm.last
            } else {
                parts.year = Int(when)
            }
            var modified = calendar.date(from: parts)
            if when.contains(":"), let date = modified, date > now.addingTimeInterval(86_400) {
                parts.year = (parts.year ?? 0) - 1
                modified = calendar.date(from: parts)
            }
            items.append(FolderItem(url: RemoteURL.child(of: folder, named: name), name: name, isFolder: isFolder,
                                    size: isFolder ? nil : Int64(text(2)), modified: modified,
                                    kind: FolderItem.kind(forFileNamed: name, isFolder: isFolder)))
        }
        return items
    }

    /// Reads what `ssh`/`sftp` printed when it failed, as an error with words a person can act on.
    public static func classify(stderr: String) -> RemoteError {
        let text = stderr.lowercased()
        if text.contains("host identification has changed") { return .hostKeyChanged }
        if text.contains("host key verification failed") { return .other("host key unknown") }
        if text.contains("permission denied") || text.contains("too many authentication failures") { return .denied("Access denied.") }
        if text.contains("no such file") || text.contains("not found") { return .other("That folder does not exist.") }
        let lost = ["connection refused", "timed out", "could not resolve", "no route to host", "connection closed",
                    "broken pipe", "connection reset", "network is unreachable", "lost connection"]
        if lost.contains(where: text.contains) { return .connectionLost }
        let first = stderr.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return .other(first.isEmpty ? "The server answered with an error." : first)
    }

    /// The `SHA256:…` part of `ssh-keygen -lf` output, like "256 SHA256:abc host (ED25519)".
    public static func fingerprint(fromKeygen output: String) -> String? {
        output.split(whereSeparator: \.isWhitespace).map(String.init).first { $0.hasPrefix("SHA256:") || $0.hasPrefix("MD5:") }
    }

    /// The key line to trust from `ssh-keyscan` output: ed25519 first, else the first key.
    public static func preferredKeyLine(fromKeyscan output: String) -> String? {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.hasPrefix("#") && !$0.isEmpty }
        return lines.first { $0.contains(" ssh-ed25519 ") } ?? lines.first
    }
}
