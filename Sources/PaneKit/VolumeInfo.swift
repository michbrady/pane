import Foundation

/// A mounted disk: the startup disk, an external drive, or a network share.
public struct VolumeInfo: Equatable, Sendable {
    public let url: URL
    public let name: String
    /// False for a network share.
    public let isLocal: Bool
    /// True when it can be ejected: an external drive or a share.
    public let isEjectable: Bool

    public init(url: URL, name: String, isLocal: Bool, isEjectable: Bool) {
        self.url = url
        self.name = name
        self.isLocal = isLocal
        self.isEjectable = isEjectable
    }

    /// Every volume that is mounted and meant to be seen.
    public static func mounted() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsLocalKey, .volumeIsEjectableKey, .volumeIsRemovableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url -> VolumeInfo? in
            guard !url.path.hasPrefix("/System/Volumes"), let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let isLocal = values.volumeIsLocal ?? true
            let ejectable = !isLocal || values.volumeIsEjectable == true || values.volumeIsRemovable == true
            return VolumeInfo(url: url.standardizedFileURL, name: values.volumeName ?? url.lastPathComponent,
                              isLocal: isLocal, isEjectable: ejectable)
        }
    }

    /// True when a folder lives on a network share.
    public static func isNetwork(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == false
    }
}

public enum VolumeSections {
    /// Local volumes go under This Mac and shares under Network. The startup disk comes first.
    public static func split(_ volumes: [VolumeInfo]) -> (drives: [VolumeInfo], network: [VolumeInfo]) {
        let drives = volumes.filter(\.isLocal).sorted { a, b in
            if (a.url.path == "/") != (b.url.path == "/") { return a.url.path == "/" }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        let network = volumes.filter { !$0.isLocal }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (drives, network)
    }
}

/// How often to look again at a folder, when the system cannot say that it changed.
public enum PollPolicy {
    /// Network shares do not report changes reliably, so look every ten seconds. Local folders report them.
    public static func interval(isLocal: Bool) -> TimeInterval? {
        isLocal ? nil : 10
    }
}
