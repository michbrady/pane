# Architecture review after M5, 2026-10-31

Check-in after M5 System (434e19b), before M6 Remote servers. 6,535 lines of
Swift. Largest: `AppModel.swift` 468, `FileActions.swift` 354, `FileOperations.swift`
283, `FolderTab.swift` 281. The self-test is now six small files (812 lines in all)
and runs in about 40 seconds. M5 reused the existing seams: `FileSystem` for new
places, `FolderTab` per tab, plain `PaneKit` types for every rule. It added no
new kind of problem.

## Move the places out of AppModel  [Strong]

Files: Sources/Pane/AppModel.swift (468 lines, about 90 members)
Signal: it is the biggest file by 114 lines, it grew 100 lines in M5 alone, and
M6 adds remote connections to the same tree. This is the "one feature touches
many places" signal: every new place (drive, share, cloud folder, server) changes
the same class.
Problem: `AppModel` mixes four jobs. Tabs. The Navigation pane's places (Quick
access pins, This Mac, drives, Network, Cloud, eject, the tree selection). Connecting
to a server (sheet state, recents, mount, Keychain). System hooks (global shortcut,
folder handler, Full Disk Access guide, Terminal, open from another app). M6's
FTP, SFTP, and S3 connections would add a fifth set of members to the second and
third jobs.
Proposal: `Places` owns the Navigation pane's roots and everything that adds a
row to it. `Connections` owns Connect to Server and, in M6, the saved servers. The
system hooks stay in a smaller `AppModel` or move to `SystemHooks`.

```swift
@Observable final class Places {            // the Navigation pane
    var quickRoots, driveRoots, networkRoots, cloudRoots: [NavNode]
    var expanded: Set<String>; var navSelection: String?
    func pin(_:at:), unpin(_:), refreshVolumes(), eject(_:), syncTree(for folder:)
}
@Observable final class Connections {       // M5: SMB. M6: FTP, SFTP, S3
    var recentServers; var isConnecting; var connectError
    func connect(address:user:password:remember:)
}
```

Benefits: Locality (a new kind of place touches `Places` and `Connections`, not
the tab code). Leverage (M6's saved connections list is one more array on
`Places`). `AppModel` drops to about 200 lines. Tests for places and connecting
stay in the same two self-test files.
Proof of same behavior: the 189 self-test checks and 73 unit tests pass unchanged
apart from `model.x` becoming `model.places.x` or `model.connections.x`, and the
snapshots do not change.
Plan, one commit per step: 1) move pins, volumes, cloud, eject, and tree sync
into `Places`. 2) move Connect to Server into `Connections`. 3) point the views
and menus at them.

## Folder-handler and shortcut code is near the system  [Speculative]

`SystemFolderHandler`, `GlobalHotKey`, `SystemSpotlight`, `QuickLookController`,
`SMBMount`, and `PasswordKeychain` are the app's wrappers around the Mac. They are
small, replaceable in tests, and in one folder's worth of files. If a fourth or
fifth wrapper arrives, give them a `System/` folder.

## Considered, not recommended

- Splitting `FileActions` (354 lines). It is one job, and each method is short.
- Moving `NavNode` into `PaneKit`. It uses `Locations`, which is app code.
- Collapsing the `Wait.settle` quiet period to save seconds. The suite is fast
  enough, and a shorter quiet time is what made the first version flaky.
