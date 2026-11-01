import Foundation

/// Waiting for the app inside the self-test. A check waits until its state is true, not for a fixed time.
@MainActor
enum Wait {
    /// Polls until `condition` is true, then returns true at once. False after `timeout` seconds.
    @discardableResult
    static func until(_ timeout: Double = 4, _ condition: () -> Bool) async -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return condition()
    }

    /// Waits until nothing is loading, searching, or running, and stays that way for `quiet` seconds.
    /// The quiet time covers the folder watcher's short delay and the Table's own settling.
    static func settle(_ model: AppModel, quiet: Double = 0.4, timeout: Double = 8) async {
        let deadline = Date.now.addingTimeInterval(timeout)
        var quietSince: Date?
        while Date.now < deadline {
            let busy = model.tab.isLoading || model.tab.isSearchRunning || model.actions.isBusy
            if busy {
                quietSince = nil
            } else if let since = quietSince {
                if Date.now.timeIntervalSince(since) >= quiet { return }
            } else {
                quietSince = .now
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
    }
}
