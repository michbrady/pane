import AppKit
import Foundation
import Observation
import PaneKit

/// The Navigation pane's places: the Quick access pins, This Mac (the home folder and drives), Network
/// shares, and Cloud folders. It also keeps the tree on the folder being shown. A new kind of place,
/// like a server, adds rows here and nowhere else.
@Observable
final class Places {
    private(set) var quickRoots: [NavNode]
    private var pins: PinStore
    let homeRoot: NavNode
    private(set) var driveRoots: [NavNode] = []
    private(set) var networkRoots: [NavNode] = []
    /// iCloud Drive and the cloud services installed on this Mac.
    private(set) var cloudRoots: [NavNode] = []
    /// The servers connected now, each as a row under Connections.
    private(set) var connectionRoots: [NavNode] = []
    var thisMacRoots: [NavNode] { [homeRoot] + driveRoots }
    /// Where the mounted volumes come from. Tests use a fake list, so they see the same on every Mac.
    var volumeSource: () -> [VolumeInfo] = { Locations.isOverridden ? [] : VolumeInfo.mounted() }
    var expanded: Set<String> {
        didSet { Prefs.defaults.set(Array(expanded), forKey: "pane.expanded") }
    }
    var navSelection: String?

    // What the places need from the window. AppModel fills these in.
    var currentFolder: () -> URL = { Locations.home }
    var goTo: (URL) -> Void = { _ in }
    /// Called after the volumes change, so a tab on a folder that went away can say so.
    var volumesChanged: () -> Void = {}
    var alert: (String) -> Void = { _ in }
    var serverKeys: () -> [String] = { [] }
    var disconnect: (String) -> Void = { _ in }

    init() {
        let defaults = Prefs.defaults
        let store = PinStore(saved: defaults.array(forKey: "pane.pins") as? [Data], defaults: Locations.quickAccess)
        pins = store
        quickRoots = store.urls.map { NavNode(url: $0, prefix: "quick:") }
        homeRoot = NavNode(url: Locations.home, prefix: "home:")
        expanded = Set(defaults.stringArray(forKey: "pane.expanded") ?? [])
    }

    /// Lists the connected servers again.
    func refreshConnections() {
        connectionRoots = serverKeys().compactMap { key in
            URL(string: key + "/").map { NavNode(url: $0, prefix: "conn:", name: Self.serverName(key), ejectable: true) }
        }
        syncTree()
    }

    /// "sftp://me@nas" shows as "nas (SFTP)".
    static func serverName(_ key: String) -> String {
        guard let url = URL(string: key), let host = url.host else { return key }
        return "\(host) (\(url.scheme?.uppercased() ?? ""))"
    }

    /// Reads the volumes now, and again whenever a drive or share mounts, unmounts, or is renamed.
    func start() {
        refreshVolumes()
        guard !Locations.isOverridden else { return }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshVolumes() }
            }
        }
    }

    // MARK: Quick access

    func isPinned(_ url: URL) -> Bool { pins.contains(url) }

    func pin(_ url: URL, at index: Int? = nil) {
        pins.pin(url, at: index)
        pinsChanged()
    }

    func unpin(_ url: URL) {
        pins.unpin(url)
        pinsChanged()
    }

    private func pinsChanged() {
        Prefs.defaults.set(pins.bookmarks, forKey: "pane.pins")
        refreshPins()
        syncTree()
    }

    /// Rebuilds the Quick access rows when a pinned folder was renamed or moved.
    func refreshPins() {
        let urls = pins.urls
        guard urls.map(\.path) != quickRoots.map(\.url.path) else { return }
        quickRoots = urls.map { NavNode(url: $0, prefix: "quick:") }
    }

    // MARK: The tree

    /// Expands the folders above the current one and selects its row.
    func syncTree() {
        let url = currentFolder()
        // A folder on a server selects that server's row. There is nothing above it to expand.
        if RemoteURL.isRemote(url) {
            navSelection = "conn:" + RemoteURL.serverKey(url) + "/"
            return
        }
        // The root that holds this folder: the home folder, a drive, or a share. The deepest one wins.
        let roots: [(prefix: String, path: String)] =
            [("home:", Locations.home.path)] + driveRoots.map { ("vol:", $0.url.path) } + networkRoots.map { ("net:", $0.url.path) }
            + cloudRoots.map { ("cloud:", $0.url.path) } + [("vol:", "/")]
        let holder = roots.filter { url.path == $0.path || url.path.hasPrefix($0.path == "/" ? "/" : $0.path + "/") }
            .max { $0.path.count < $1.path.count } ?? ("vol:", "/")
        let pinned = quickRoots.contains { $0.url.path == url.path }
        navSelection = pinned ? "quick:" + url.path : holder.prefix + url.path
        for ancestor in Breadcrumbs.chain(for: url).dropLast()
        where ancestor.path.count >= holder.path.count && (ancestor.path == holder.path || ancestor.path.hasPrefix(holder.path == "/" ? "/" : holder.path + "/")) {
            expanded.insert(holder.prefix + ancestor.path)
        }
    }

    /// Row id to folder, for a click in the Navigation pane.
    static func url(forNavID id: String) -> URL? {
        guard let colon = id.firstIndex(of: ":") else { return nil }
        let rest = String(id[id.index(after: colon)...])
        return rest.contains("://") ? URL(string: rest) : URL(fileURLWithPath: rest)
    }

    // MARK: Drives, shares, and cloud folders

    /// Reads the mounted volumes again: drives go under This Mac and shares under Network.
    func refreshVolumes() {
        let sections = VolumeSections.split(volumeSource())
        driveRoots = sections.drives.map { NavNode(url: $0.url, prefix: "vol:", name: $0.name, ejectable: $0.isEjectable) }
        networkRoots = sections.network.map { NavNode(url: $0.url, prefix: "net:", name: $0.name, ejectable: true) }
        let cloud = CloudLocations.list(home: Locations.home)
        Locations.cloudNames = Dictionary(uniqueKeysWithValues: cloud.map { ($0.url.path, $0.name) })
        cloudRoots = cloud.map { NavNode(url: $0.url, prefix: "cloud:", name: $0.name) }
        volumesChanged()
        syncTree()
    }

    /// The eject button beside a drive or share. A busy volume says so and stays.
    func eject(_ node: NavNode) {
        // The button on a server's row closes the connection.
        if node.id.hasPrefix("conn:") {
            disconnect(RemoteURL.serverKey(node.url))
            return
        }
        let url = node.url
        let name = node.name
        if currentFolder().path.hasPrefix(url.path) { goTo(Locations.home) }
        Task {
            do {
                try await Task.detached { try NSWorkspace.shared.unmountAndEjectDevice(at: url) }.value
            } catch {
                alert("Unable to eject \u{201C}\(name)\u{201D}. Items are in use.")
            }
            refreshVolumes()
        }
    }
}
