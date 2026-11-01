import Foundation

/// The "Show in Pane" service can be given text, like a path someone selected in a terminal or a document.
/// This turns that text into file addresses. Pure: it does not look at the disk.
public enum ServicePaths {
    /// One address per line. Reads `/path`, `~/path`, `file:///path`, and paths in quotes. Skips anything else.
    public static func urls(fromText text: String, home: String) -> [URL] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            var piece = line.trimmingCharacters(in: .whitespaces)
            piece = piece.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
            guard !piece.isEmpty else { return nil }
            if piece.hasPrefix("file://") { return URL(string: piece).flatMap { $0.isFileURL ? $0 : nil } }
            if piece == "~" { return URL(fileURLWithPath: home) }
            if piece.hasPrefix("~/") { return URL(fileURLWithPath: home + String(piece.dropFirst(1))) }
            return piece.hasPrefix("/") ? URL(fileURLWithPath: piece) : nil
        }
    }
}
