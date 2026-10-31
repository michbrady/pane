import Foundation

/// One finished change to the file system, kept so Undo and Redo can reverse it.
public struct OperationRecord: Sendable {
    public enum Step: Sendable, Equatable {
        case copy(source: URL, destination: URL)
        case move(from: URL, to: URL)
        /// `trashed` is where the item went, once it has been trashed.
        case trash(original: URL, trashed: URL?)
        case rename(from: URL, to: URL)
        case makeFolder(URL)
    }

    /// The Edit menu shows it: "Undo Move 3 Items".
    public var name: String
    public var steps: [Step]

    public init(name: String, steps: [Step]) {
        self.name = name
        self.steps = steps
    }

    public var isEmpty: Bool { steps.isEmpty }

    public static func title(_ verb: String, count: Int, firstName: String?) -> String {
        count == 1 ? "\(verb) \u{201C}\(firstName ?? "Item")\u{201D}" : "\(verb) \(count) Items"
    }
}
