import PaneKit
import SwiftUI

/// Cmd-I: what an item is, how big, when, and where. A folder's total is measured in the
/// background, with a spinner. With several items selected it shows their combined size.
struct PropertiesSheet: View {
    let model: AppModel
    let urls: [URL]

    @State private var items: [ItemProperties] = []
    @State private var total: FolderTotal?
    @State private var measuring = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(spacing: Space.md) {
                Image(nsImage: IconCache.icon(for: urls.first ?? Locations.home, isFolder: items.first?.isFolder ?? true))
                    .resizable()
                    .frame(width: Layout.gridIcon, height: Layout.gridIcon)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.headline).lineLimit(2).truncationMode(.middle)
                    Text(subtitle).foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.lg, verticalSpacing: Space.sm) {
                ForEach(rows, id: \.0) { row in
                    GridRow {
                        Text(row.0).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text(row.1).textSelection(.enabled).lineLimit(3)
                    }
                }
                if measuring {
                    GridRow {
                        Text("Size").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        HStack(spacing: Space.sm) {
                            ProgressView().controlSize(.small)
                            Text("Calculating…").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack {
                Text("Tags").foregroundStyle(.secondary)
                TagDots(tags: Array(commonTags))
                TagMenu(model: model, urls: urls) { items = urls.compactMap(ItemProperties.read) }
                    .fixedSize()
                Spacer()
            }
            HStack {
                Spacer()
                Button("Done") { model.closeProperties() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: Layout.sheetWidth)
        .noInitialFocus()
        .task { await load() }
    }

    /// Tags every selected item has.
    private var commonTags: [String] {
        guard let first = items.first else { return [] }
        return first.tags.filter { tag in items.allSatisfy { $0.tags.contains(tag) } }
    }

    private var single: ItemProperties? { items.count == 1 ? items.first : nil }

    private var title: String { single?.name ?? (items.count > 1 ? "\(items.count) Items" : "") }

    private var subtitle: String {
        if let single { return single.kind }
        return items.isEmpty ? "" : "Selection"
    }

    /// Label and value pairs, in the order shown.
    private var rows: [(String, String)] {
        var result: [(String, String)] = []
        if let single {
            result.append(("Where", single.location))
        }
        if let bytes = totalBytes {
            result.append(("Size", Self.sizeText(bytes)))
            if let disk = totalOnDisk { result.append(("Size on disk", Self.sizeText(disk))) }
        }
        if let single {
            result.append(("Created", single.created.map(Format.date) ?? "—"))
            result.append(("Modified", single.modified.map(Format.date) ?? "—"))
            result.append(("Permissions", single.permissions))
        }
        if let total, !measuring {
            result.append(("Contains", "\(total.files) \(total.files == 1 ? "file" : "files"), \(total.folders) \(total.folders == 1 ? "folder" : "folders")"))
        }
        return result
    }

    private var totalBytes: Int64? {
        guard !measuring else { return nil }
        return items.compactMap(\.size).reduce(0, +) + (total?.bytes ?? 0)
    }

    private var totalOnDisk: Int64? {
        guard !measuring else { return nil }
        return items.compactMap(\.sizeOnDisk).reduce(0, +) + (total?.bytesOnDisk ?? 0)
    }

    private static func sizeText(_ bytes: Int64) -> String {
        let short = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return bytes < 1000 ? short : "\(short) (\(bytes.formatted()) bytes)"
    }

    private func load() async {
        items = urls.compactMap(ItemProperties.read)
        let folders = zip(urls, items).filter { $0.1.isFolder }.map(\.0)
        guard !folders.isEmpty else { return }
        measuring = true
        var sum = FolderTotal()
        for folder in folders {
            let part = await FolderTotal.measureInBackground(folder)
            sum.bytes += part.bytes
            sum.bytesOnDisk += part.bytesOnDisk
            sum.files += part.files
            sum.folders += part.folders
        }
        total = sum
        measuring = false
    }
}
