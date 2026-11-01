import Foundation

/// The two settings that decide which app opens folders for other apps: the file viewer in the
/// global preferences (what "Show in Finder" calls), and the app that opens folders by default.
@MainActor
public protocol FolderHandlerSystem: AnyObject {
    func fileViewer() -> String?
    func setFileViewer(_ bundleID: String?)
    func folderHandler() -> String?
    func setFolderHandler(_ bundleID: String) async
}

/// What was there before Pane took over, so turning it off puts it back.
public struct FolderHandlerState: Codable, Equatable, Sendable {
    public var isOn = false
    public var previousFileViewer: String?
    public var previousFolderHandler: String?

    public init() {}
}

@MainActor
public enum FolderHandlerSwitch {
    public static let finder = "com.apple.finder"

    /// Makes `bundleID` the app that opens folders. The first time, it remembers what was set before.
    /// Turning on twice never overwrites that memory with Pane itself.
    public static func turnOn(_ system: FolderHandlerSystem, as bundleID: String, state: inout FolderHandlerState) async {
        if !state.isOn {
            state.previousFileViewer = system.fileViewer()
            state.previousFolderHandler = system.folderHandler()
            state.isOn = true
        }
        system.setFileViewer(bundleID)
        await system.setFolderHandler(bundleID)
    }

    /// Puts back what was there. With nothing remembered, Finder is the folder app and there is no file viewer.
    public static func turnOff(_ system: FolderHandlerSystem, state: inout FolderHandlerState) async {
        guard state.isOn else { return }
        system.setFileViewer(state.previousFileViewer)
        await system.setFolderHandler(state.previousFolderHandler ?? finder)
        state = FolderHandlerState()
    }
}

/// A stand-in for the system, for tests: it keeps the two settings in memory.
@MainActor
public final class InMemoryFolderHandlerSystem: FolderHandlerSystem {
    public var viewer: String?
    public var handler: String?

    public init(viewer: String? = nil, handler: String? = FolderHandlerSwitch.finder) {
        self.viewer = viewer
        self.handler = handler
    }

    public func fileViewer() -> String? { viewer }
    public func setFileViewer(_ bundleID: String?) { viewer = bundleID }
    public func folderHandler() -> String? { handler }
    public func setFolderHandler(_ bundleID: String) async { handler = bundleID }
}
