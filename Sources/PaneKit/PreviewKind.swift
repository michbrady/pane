import Foundation
import UniformTypeIdentifiers

/// How the preview pane shows a file.
public enum PreviewKind: Sendable, Equatable {
    case image, pdf, text, other

    public static func kind(for url: URL) -> PreviewKind {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) || type.conforms(to: .xml) { return .text }
        return .other
    }

    /// The first part of a text file, for the preview. Long files stop at `limit` bytes.
    public static func textPreview(of url: URL, limit: Int = 64 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
