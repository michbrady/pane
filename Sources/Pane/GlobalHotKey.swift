import AppKit
import Carbon.HIToolbox
import Observation
import PaneKit
import SwiftUI

/// The shortcut that opens Pane from any app, through the system hot-key API. That API needs no
/// Accessibility permission. If another app already owns the shortcut, registering fails and the
/// reason is shown in Settings.
@Observable
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    var shortcut: Shortcut { didSet { save(); registerIfEnabled() } }
    var isEnabled: Bool { didSet { save(); registerIfEnabled() } }
    /// Why the shortcut is not working, or nil.
    private(set) var problem: String?
    /// Runs on the main thread when the shortcut is pressed.
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {
        let defaults = Prefs.defaults
        if let data = defaults.data(forKey: "pane.globalShortcut"), let saved = try? JSONDecoder().decode(Shortcut.self, from: data), saved.isValid {
            shortcut = saved
        } else {
            shortcut = .default
        }
        isEnabled = defaults.object(forKey: "pane.globalShortcutOn") as? Bool ?? true
    }

    /// Starts listening. Tests and snapshots never grab a shortcut on their own.
    func start() {
        guard !Locations.isOverridden else { return }
        installHandler()
        registerIfEnabled()
    }

    /// Registers the shortcut now. Returns the system's answer: 0 is success.
    @discardableResult
    func register() -> OSStatus {
        installHandler()
        unregister()
        let id = EventHotKeyID(signature: OSType(0x50414E45), id: 1)   // "PANE"
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        problem = status == noErr ? nil
            : status == OSStatus(eventHotKeyExistsErr) ? "\(shortcut.displayText) is already used by another app. Choose a different shortcut."
            : "The shortcut could not be set (error \(status))."
        return status
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func registerIfEnabled() {
        guard handlerRef != nil else { return }
        if isEnabled { register() } else { unregister(); problem = nil }
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in GlobalHotKey.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    private func save() {
        let defaults = Prefs.defaults
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: "pane.globalShortcut")
        defaults.set(isEnabled, forKey: "pane.globalShortcutOn")
    }
}

/// A button that records the next key combination typed, for changing the shortcut.
struct ShortcutRecorder: View {
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?
    let hotKey: GlobalHotKey

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.xs) {
            Button(recording ? "Press a shortcut…" : hotKey.shortcut.displayText) { recording ? stop() : start() }
                .help("Click, then press the keys you want. Escape cancels.")
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }   // Escape
            var bits: UInt32 = 0
            if event.modifierFlags.contains(.command) { bits |= Shortcut.command }
            if event.modifierFlags.contains(.option) { bits |= Shortcut.option }
            if event.modifierFlags.contains(.control) { bits |= Shortcut.control }
            if event.modifierFlags.contains(.shift) { bits |= Shortcut.shift }
            let candidate = Shortcut(keyCode: UInt32(event.keyCode), modifiers: bits)
            if candidate.isValid {
                hotKey.shortcut = candidate
                stop()
            } else {
                message = "Hold Command, Option, or Control with a letter or number."
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
