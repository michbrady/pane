import Foundation

/// A keyboard shortcut that works from any app: a key and the modifier keys held with it.
public struct Shortcut: Codable, Equatable, Sendable {
    /// The virtual key code, like 14 for E.
    public var keyCode: UInt32
    /// Carbon modifier bits: command 256, shift 512, option 2048, control 4096.
    public var modifiers: UInt32

    public static let command: UInt32 = 256
    public static let shift: UInt32 = 512
    public static let option: UInt32 = 2048
    public static let control: UInt32 = 4096

    /// Control-Option-E, like Win+E in spirit: open a fresh Pane.
    public static let `default` = Shortcut(keyCode: 14, modifiers: control | option)

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A shortcut that works everywhere needs Command, Option, or Control with the key. Shift alone
    /// would take over ordinary typing.
    public var isValid: Bool {
        modifiers & (Shortcut.command | Shortcut.option | Shortcut.control) != 0 && Shortcut.keyNames[keyCode] != nil
    }

    /// Like "⌃⌥E".
    public var displayText: String {
        var text = ""
        if modifiers & Shortcut.control != 0 { text += "⌃" }
        if modifiers & Shortcut.option != 0 { text += "⌥" }
        if modifiers & Shortcut.shift != 0 { text += "⇧" }
        if modifiers & Shortcut.command != 0 { text += "⌘" }
        return text + (Shortcut.keyNames[keyCode] ?? "?")
    }

    /// Letters, digits, and a few named keys, by virtual key code.
    static let keyNames: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        49: "Space", 36: "Return", 48: "Tab",
    ]
}
