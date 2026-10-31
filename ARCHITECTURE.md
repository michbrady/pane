# Pane architecture

Two targets. `PaneKit` has no SwiftUI. `Pane` is the app and depends on it.

| Target | Holds |
| --- | --- |
| `PaneKit` | `FolderItem`, `FolderLister`, `NavigationHistory`, `PathResolver`, `Breadcrumbs`, `FileSystem`, `FileOperations`, `OperationRecord`, `DropRules`. Pure, testable with `swift test`. |
| `Pane` | `AppModel` (navigation, listing, tree, address state), views, `Locations` and `Prefs`, `FolderWatcher`, `NavNode`, snapshot and self-test modes. |

Data flow: `AppModel.go(to:)` updates `NavigationHistory`, reloads the
listing on a background task through `FolderLister`, and watches the folder
with `FolderWatcher`. Views read `AppModel` and call its methods.

Test mode: `APP_HOME=<dir in /tmp>` makes `Locations` and `Prefs` use a
throwaway home folder and settings suite.

## File operations

`FileSystem` (in `PaneKit`) is the seam: `LocalFileSystem` is this Mac, `InMemoryFileSystem` is for tests. FTP, SFTP,
and S3 become more adapters in M6. `FileOperations` takes a `FileSystem` and does paste (copy and move), conflicts,
Trash, delete, rename, and new folder. Each change returns an `OperationRecord` that Undo and Redo reverse.
`DropRules` picks move or copy for a drag. The app turns records into `UndoManager` steps, one group each.

`Clipboard` puts real file URLs on the pasteboard, so Finder can paste them, and remembers what was cut.

Next: `docs/architecture-review-2026-10-31-m2.md` recommends splitting `AppModel` into `FolderTab` and `FileActions`
before tabs (S-026).
