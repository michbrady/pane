# Pane architecture

Two targets. `PaneKit` has no SwiftUI. `Pane` is the app and depends on it.

| Target | Holds |
| --- | --- |
| `PaneKit` | `FolderItem`, `FolderLister`, `NavigationHistory`, `PathResolver`, `Breadcrumbs`. Pure, testable with `swift test`. |
| `Pane` | `AppModel` (navigation, listing, tree, address state), views, `Locations` and `Prefs`, `FolderWatcher`, `NavNode`, snapshot and self-test modes. |

Data flow: `AppModel.go(to:)` updates `NavigationHistory`, reloads the
listing on a background task through `FolderLister`, and watches the folder
with `FolderWatcher`. Views read `AppModel` and call its methods.

Test mode: `APP_HOME=<dir in /tmp>` makes `Locations` and `Prefs` use a
throwaway home folder and settings suite.

Seams to add: a `FileSystem` protocol in `PaneKit` with local and fake
adapters in M2 (S-010), then FTP, SFTP, and S3 adapters in M6. See
`docs/architecture-review-2026-10-31.md`.
