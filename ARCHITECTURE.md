# Pane architecture

Two targets. `PaneKit` has no SwiftUI. `Pane` is the app and depends on it.

| Target | Holds |
| --- | --- |
| `PaneKit` | `FolderItem`, `FolderLister`, `NavigationHistory`, `PathResolver`, `Breadcrumbs`, `FileSystem`, `FileOperations`, `OperationRecord`, `DropRules`, `FolderSorter`, `PinStore`, `FileSearch`, `TagEditor`, `ItemProperties`, `PreviewKind`, `SelectionSummary`, `VolumeInfo`, `CloudLocations`, `SMBAddress`, `Shortcut`, `FolderHandler`. Pure, testable with `swift test`. |
| `Pane` | `AppModel` (the tabs, the Navigation pane, the Address bar, Quick access pins), `FolderTab` (one folder: history, listing, selection, watcher), `FileActions` (clipboard, operations, sheets, undo, for the active tab), `ViewSettings` (sort, view mode, hidden files, columns), views, `Locations` and `Prefs`, `FolderWatcher`, `NavNode`, snapshot and self-test modes. |

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

Views: `FolderContent` picks Details, List, or Icons. `PreviewPane`, `PropertiesSheet`, `TagViews`, and `TabStrip` are separate files. `QuickLookController` and `SystemSpotlight` wrap system APIs.

The wrappers around the Mac are `SystemSpotlight`, `SMBMount` and `PasswordKeychain`, `GlobalHotKey`, `SystemFolderHandler`, and `QuickLookController`. Each has a plain `PaneKit` type for its rules and a fake for tests, so the self-test never changes your Mac, network, or Keychain.

Reviews: `docs/architecture-review-2026-10-31-m5.md` recommends moving the Navigation pane's places and connecting into their own types before M6. `docs/architecture-review-2026-10-31-m4.md` recommends a faster, steadier self-test. `docs/architecture-review-2026-10-31-m2.md` split `AppModel` into `FolderTab` and `FileActions` before tabs. `docs/architecture-review-2026-10-31-m3.md` found nothing to change after M3.
