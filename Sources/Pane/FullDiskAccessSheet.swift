import PaneKit
import SwiftUI

/// The first-run screen: why Pane asks for Full Disk Access, and a button that opens the right
/// page in System Settings. Pane still works without it. macOS then asks about each folder.
struct FullDiskAccessSheet: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(spacing: Space.md) {
                Image(systemName: "lock.open.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Allow Full Disk Access").font(.headline)
                    Text(FullDiskAccessGuide.reason).foregroundStyle(.secondary)
                }
            }
            Text("Turn on Pane in Privacy & Security > Full Disk Access, then reopen Pane. Without it, Pane still works and macOS asks about each folder.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Not Now") { model.dismissFullDiskAccessGuide() }
                    .keyboardShortcut(.cancelAction)
                Button("Open System Settings") { model.dismissFullDiskAccessGuide(openSettings: true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: Layout.sheetWidth)
        .noInitialFocus()
    }
}
