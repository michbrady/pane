import Foundation

/// Calls back when the contents of one folder change.
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?

    func watch(_ url: URL, onChange: @escaping @MainActor () -> Void) {
        stop()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        source.setEventHandler { Task { @MainActor in onChange() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
