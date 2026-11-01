# Pane architecture

Two targets. `PaneKit` has no SwiftUI. `Pane` is the app and depends on it.

| Target | Holds |
| --- | --- |
| `PaneKit` | `FolderItem`, `FolderLister`, `NavigationHistory`, `PathResolver`, `Breadcrumbs`, `FileSystem`, `FileOperations`, `OperationRecord`, `DropRules`, `FolderSorter`, `PinStore`, `FileSearch`, `TagEditor`, `ItemProperties`, `PreviewKind`, `SelectionSummary`, `VolumeInfo`, `CloudLocations`, `SMBAddress`, `Shortcut`, `FolderHandler`, and the server layer: `RemoteURL`, `RemoteFileSystem`, `FileSystemRouter`, `InMemoryRemote`, `S3FileSystem` with `S3Signer` and `S3Listing`, `SFTPFileSystem`, `FTPFileSystem`, `ProcessRunner`, `TransferOperations`, `TransferStats`, `RemoteEdits`, `SavedConnection`, `ConnectionForm`, `SecretStore`, `ContextMenuPlan`, `FocusCycle`, `ItemSpeech`. Pure, testable with `swift test`. |
| `Pane` | `AppModel` (the tabs, the Address bar, and the small system hooks), `Places` (the Navigation pane's rows: Quick access pins, This Mac, drives, Network, Cloud, eject, and the tree selection), `Connections` (Connect to Server: the sheet state, the recent list, the mount, one `connect(form)` for FTP, SFTP, and S3, the saved list, and the router), `FolderTab` (one folder: history, listing, selection, watcher), `FileActions` (clipboard, operations, sheets, undo, for the active tab), `ViewSettings` (sort, view mode, hidden files, columns), views, `Locations` and `Prefs`, `FolderWatcher`, `NavNode`, snapshot and self-test modes. |

Data flow: `AppModel.go(to:)` updates `NavigationHistory`, reloads the
listing on a background task through `FolderLister`, and watches the folder
with `FolderWatcher`. Views read `AppModel` and call its methods.

Test mode: `APP_HOME=<dir in /tmp>` makes `Locations` and `Prefs` use a
throwaway home folder and settings suite.

## File operations

`FileSystem` (in `PaneKit`) is the seam: `LocalFileSystem` is this Mac, `InMemoryFileSystem` is for tests. FTP, SFTP,
and S3 are more adapters, through `RemoteFileSystem` (see Servers). `FileOperations` takes a `FileSystem` and does paste (copy and move), conflicts,
Trash, delete, rename, and new folder. Each change returns an `OperationRecord` that Undo and Redo reverse.
`DropRules` picks move or copy for a drag. The app turns records into `UndoManager` steps, one group each.

`Clipboard` puts real file URLs on the pasteboard, so Finder can paste them, and remembers what was cut.

## Servers (M6)

A place on a server is a URL: `sftp://host/folder`, `ftp://`, `ftps://`, `s3://host/bucket/key`. `RemoteURL` keeps them tidy. `FileSystemRouter` (owned by `AppModel`) holds the open connections by `scheme://host:port` and picks the file system for any URL, so a server address never reaches a local file call. `RemoteFileSystem` is the seam, and adds `upload`, `download`, `reconnect`, and `disconnect` to `FileSystem`. Adapters: `S3FileSystem` (URLSession with a Signature Version 4 signer), `SFTPFileSystem` (system `sftp` over one shared ssh connection, with Pane's own list of trusted servers), `FTPFileSystem` (system `curl`), and `InMemoryRemote` for tests. The process-based ones run through `ProcessRunner`, so tests give a scripted one.

`FileOperations` works on any `FileSystem`, so rename, New Folder, and delete on a server use it unchanged, and do not register Undo. `TransferOperations` handles copy and move between this Mac and servers: it walks folders first, keeps conflicts and Cut safe, throttles progress, and removes part files on a cancel or a failure. `RemoteEdits` keeps the temporary copies for Open on a server, notices saves, and checks the server's copy has not changed before it uploads. `SavedConnection` holds only settings; secrets live in the Keychain (`PasswordKeychain`).

A remote `FolderTab` does not watch or poll. Its states are the usual ones plus Loading with Cancel, Connection lost with Reconnect, and Not connected.

Views: `FolderContent` picks Details, List, or Icons. `PreviewPane`, `PropertiesSheet`, `TagViews`, and `TabStrip` are separate files. `QuickLookController` and `SystemSpotlight` wrap system APIs.

The wrappers around the Mac are `SystemSpotlight`, `SMBMount` and `PasswordKeychain`, `GlobalHotKey`, `SystemFolderHandler`, and `QuickLookController`. Each has a plain `PaneKit` type for its rules and a fake for tests, so the self-test never changes your Mac, network, or Keychain.

Reviews: `docs/architecture-review-2026-11-01-m7.md` found nothing Strong after M7. `docs/architecture-review-2026-11-01-m6.md` recommends one connect flow with a `SecretStore` seam, and one test file per area. `docs/architecture-review-2026-10-31-m5.md` moved the Navigation pane's places into `Places` and connecting into `Connections` before M6 (done: `AppModel` went from 468 to 307 lines). `docs/architecture-review-2026-10-31-m4.md` recommends a faster, steadier self-test. `docs/architecture-review-2026-10-31-m2.md` split `AppModel` into `FolderTab` and `FileActions` before tabs. `docs/architecture-review-2026-10-31-m3.md` found nothing to change after M3.
