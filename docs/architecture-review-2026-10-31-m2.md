# Architecture review after M2, 2026-10-31

Check-in after M2 Move files (ee07f04), before M3 Views and tabs. 3,212 lines
of Swift. The last review's top recommendation (build file operations in
`PaneKit` behind a `FileSystem` seam) was done in S-010 and held up: copy,
move, conflicts, Trash, rename, and undo are tested with no UI.

## Split AppModel into a tab and a file-actions object  [Strong]

Files: Sources/Pane/AppModel.swift (575 lines, 61 members, 9 sections)
Signal: near the 600-line trigger, and a big feature next: tabs (S-026).
Problem: one `AppModel` holds one history, one listing, one selection, and one
watcher, plus every file action. Tabs need one of the first group per tab.
Doing tabs on today's model means touching every view and menu at once.
Proposal: two types, with `AppModel` keeping app-wide state (settings, the
Navigation pane, the tab list).

```swift
@Observable final class FolderTab {          // one per tab
    var history: NavigationHistory; var items: [FolderItem]; var selection: Set<URL>
    var loadError: String?; var isLoading: Bool
    func go(to:), goBack(), goForward(), goUp(), reload()
}
@Observable final class FileActions {        // acts on the active tab
    var clipboard, progress, pendingConflict, pendingDelete, renamingURL
    func copy/cut/paste/trash/rename/newFolder/drop(in tab: FolderTab)
    // owns FileOperations and the undo registration
}
```

Benefits: Locality (a tab's state lives in one type, file actions in another).
Leverage (tabs become instances, so S-026 and S-027 are small). `AppModel`
drops under 250 lines. The self-test and snapshots call the same methods.
Proof of same behavior: the 56 self-test checks and 25 unit tests keep passing
unchanged apart from `model.x` becoming `model.tab.x`. The 24 snapshots stay
the same.
Plan, one commit per step: 1) add `FolderTab` and move navigation, listing, and
watching into it, with `AppModel.tab` as the one open tab. 2) move file actions
into `FileActions`. 3) update views and menus. Tabs then follow in S-026.

## Pure rename and tree logic in the model  [Speculative]

`syncTree` and the rename error text are pure logic inside observable classes.
Move them into `PaneKit` when they next change (S-025, S-044, S-048).

## Considered, not recommended

- A `RemoteFileSystem` protocol now. The `FileSystem` protocol already is that
  seam, with local and in-memory adapters. M6 adds the other three.
- Splitting `SelfTest.swift` (272 lines). It is a flat list of checks and reads fine.
- Replacing SwiftUI `Table` with `NSTableView`. No problem has shown up with 1,000
  items. Measure at 100,000 files before deciding (open question in the research file).
