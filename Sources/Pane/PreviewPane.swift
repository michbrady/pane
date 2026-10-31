import PDFKit
import PaneKit
import SwiftUI

/// The pane on the right: a preview of the selected file, and a summary under it.
/// It takes the model as a property, like every view that is built outside the plain view tree.
struct PreviewPane: View {
    let model: AppModel

    var body: some View {
        let selected = model.tab.selectedItems
        Group {
            if selected.isEmpty {
                ContentUnavailableView("No Selection", systemImage: "sidebar.right",
                                       description: Text("Select a file to preview it."))
            } else if selected.count == 1, let item = selected.first {
                VStack(spacing: 0) {
                    FilePreview(item: item)
                    Divider()
                    Summary(lines: Self.lines(for: item))
                }
            } else {
                VStack(spacing: Space.md) {
                    Image(systemName: "square.on.square").font(.largeTitle).foregroundStyle(.secondary)
                    Text(SelectionSummary.text(itemCount: model.tab.items.count, selected: selected)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private static func lines(for item: FolderItem) -> [(String, String)] {
        [("Name", item.name),
         ("Kind", item.kind),
         ("Size", item.size.map(Format.size) ?? "—"),
         ("Modified", item.modified.map(Format.date) ?? "—")]
    }
}

private struct Summary: View {
    let lines: [(String, String)]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.md, verticalSpacing: Space.xs) {
            ForEach(lines, id: \.0) { line in
                GridRow {
                    Text(line.0).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(line.1).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
            }
        }
        .font(.callout)
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The picture, PDF page, or text of one file. Anything else shows its icon.
private struct FilePreview: View {
    let item: FolderItem
    @State private var image: NSImage?
    @State private var text: String?
    /// True once loading finished and found nothing to show, so the icon takes over.
    @State private var failed = false

    var body: some View {
        Group {
            switch item.isFolder ? .other : PreviewKind.kind(for: item.url) {
            case .image:
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().padding(Space.md)
                } else if failed {
                    icon
                } else {
                    ProgressView()
                }
            case .pdf:
                PDFPreview(url: item.url)
            case .text:
                ScrollView {
                    Text(text ?? "")
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.md)
                }
            case .other:
                icon
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Load in the background, so a big file never freezes the window.
        .task(id: item.url) {
            image = nil
            text = nil
            failed = false
            switch PreviewKind.kind(for: item.url) {
            case .image:
                image = await Task.detached { NSImage(contentsOf: item.url) }.value
                failed = image == nil
            case .text:
                text = await Task.detached { PreviewKind.textPreview(of: item.url) }.value
            default: break
            }
        }
    }

    /// The file's icon, for anything with no preview.
    private var icon: some View {
        Image(nsImage: IconCache.icon(for: item.url, isFolder: item.isFolder))
            .resizable()
            .scaledToFit()
            .frame(width: Layout.gridIcon * 2, height: Layout.gridIcon * 2)
    }
}

private struct PDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
