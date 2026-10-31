import PaneKit
import SwiftUI

/// The dot color for a Finder tag. Tags with no standard color are gray. The name always
/// shows beside the dot, so color is never the only clue.
enum TagColor {
    static func color(_ name: String) -> Color {
        switch name {
        case "Red": .red
        case "Orange": .orange
        case "Yellow": .yellow
        case "Green": .green
        case "Blue": .blue
        case "Purple": .purple
        default: .gray
        }
    }
}

/// Colored dots, then the tag names.
struct TagDots: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: Space.xs) {
                ForEach(tags, id: \.self) { tag in
                    Circle().fill(TagColor.color(tag)).frame(width: Space.sm, height: Space.sm)
                }
                Text(tags.joined(separator: ", ")).lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tags: \(tags.joined(separator: ", "))")
        }
    }
}

/// A Tags submenu: a tag the items all have shows a checkmark. Menus are built outside the
/// view's environment, so the model is passed in.
struct TagMenu: View {
    let model: AppModel
    let urls: [URL]
    var onChange: () -> Void = {}

    var body: some View {
        let common = model.commonTags(of: urls)
        Menu("Tags") {
            ForEach(TagEditor.standard, id: \.self) { name in
                Toggle(isOn: Binding(
                    get: { common.contains(name) },
                    set: { on in
                        model.setTag(name, on: urls, add: on)
                        onChange()
                    })) {
                    Label(name, systemImage: "circle.fill")
                        .tint(TagColor.color(name))
                }
            }
            Divider()
            Button("Remove All Tags") {
                model.removeAllTags(from: urls)
                onChange()
            }
            .disabled(common.isEmpty && urls.allSatisfy { model.tags(of: $0).isEmpty })
        }
    }
}
