# Architecture check-in after M6 (servers)

Survey of 2026-11-01. M6 added FTP, SFTP, and S3 browsing, copy and edit on a server, and saved connections. 8 stories, 8 commits.

## Numbers

| Signal | Reading |
| --- | --- |
| Biggest app files | `FileActions` 553 (was 373), `SelfTestRemote` 525, `AppModel` 371 (was 307), `FolderTab` 345, `Connections` 287 (plus `Connections+Saved`) |
| Biggest test file | `FileOperationsTests.swift` 1,310 lines, 116 tests, every area in one file |
| Hot files, 30 days | `AppModel` 33 touches, `Snapshot` 31, `FileOperationsTests` 28, `SelfTest` 25 |
| Name collisions in the test file this milestone | 2 (`Counter`, `keepAsking`), found by the compiler each time |
| Keychain closures on `Connections` | 9 (`savePassword`, `savedPassword`, `saveSecret`, `savedSecret`, `saveSSHSecret`, `savedSSHSecret`, `saveFTPSecret`, `savedFTPSecret`, `deleteSecret`) |
| Dependency direction | `Pane` depends on `PaneKit`, never the other way. Held. |
| Real seams with two adapters | `FileSystem` (local, in memory), `RemoteFileSystem` (S3, SFTP, FTP, in memory), `ProcessRunner` (system, scripted), `S3Transport` (URLSession, stub). All earn their place. |

What went well: every protocol was built behind a seam first, so 116 unit tests and 291 self-test checks cover the rules without a network. The remote layer reused `FileOperations` unchanged for rename, New Folder, and delete.

## Connecting to a server is one flow, not three  [Strong]

Files: `Sources/Pane/Connections.swift` (287 lines), `Connections+Saved.swift`, `SMBMount.swift` (`PasswordKeychain`), `SelfTestRemote.swift`
Signal: a type with 32 functions and 9 closures; the same bug class twice (a check that assumed state it did not set up, in the connect flows).
Problem: `connectS3`, `connectSFTP`, and `connectFTP` each repeat host, port, and user validation, set `isConnecting`, build a file system, call `start`, save a secret, save the connection, and call `didConnect`. SFTP and FTP validate port the same way, word for word. Adding a protocol means a fourth copy and a tenth closure. `AppModel` holds the router and `connected` / `disconnect` / `openSavedConnection` / `removeSavedConnection`, which are connection logic that grew it by 64 lines.
Proposal:
```swift
// PaneKit: the rules, pure and unit-tested
public struct ConnectionForm: Sendable {
    public var kind: SavedConnection.Kind; public var host, port, user, secret: String
    public func validated() -> Result<Valid, FormError>   // "Type the user name.", "The port is a number from 1 to 65535."
}
// Pane: one seam for the Keychain, two adapters
protocol SecretStore { func save(_ secret: String, for: SavedConnection); func secret(for: SavedConnection) -> String?; func delete(for: SavedConnection) }
// Connections: one attempt(), and a small per-kind `makeServer(form) -> any RemoteFileSystem`
```
`Connections` then owns the router and the open servers, so `AppModel` only wires a connected server to a tab.
Benefits: locality (a protocol is one `makeServer` plus its fields), leverage (validation and saving written once), and the 9 closures become one `SecretStore` with `KeychainSecretStore` and `InMemorySecretStore`. Validation tests move to `swift test`, which is fast.
Proof of same behavior: the 44 connect checks in `SelfTestRemote` give the same results; the existing messages are asserted verbatim; a unit test per validation message; snapshots of `connect`, `connect-s3`, `connect-ftp`, `connect-sftp`, `connect-sftp-trust` unchanged.
Plan: (1) `SecretStore` replaces the 9 closures. (2) `ConnectionForm` and its tests move validation to `PaneKit`. (3) One `attempt()` in `Connections` with `makeServer` per kind. (4) Move the router, `connected`, `disconnect`, and the saved-connection openers from `AppModel` into `Connections`.

## One test file per area  [Strong]

Files: `Tests/PaneKitTests/FileOperationsTests.swift` (1,310 lines)
Signal: a Swift file over 1,000 lines; the same kind of mistake twice (two private helpers with the same name in one file).
Problem: Remote, S3, SFTP, FTP, transfer, and saved-connection tests all sit under the name "FileOperations". Private helpers (`ScriptedRunner`, `scratchFolder`, `serverURL`, `Counter`, `Collected`, `Collected2`) are shared by file position, so a new one can collide, and a failing test's file does not say what area it is.
Proposal: split by area, with the shared helpers in `TestSupport.swift`: `FileOperationsTests`, `RemoteURLTests`, `S3Tests`, `SFTPTests`, `FTPTests`, `TransferTests`, `RemoteEditsTests`, `SavedConnectionTests`.
Benefits: locality for every protocol change; helpers named once.
Proof of same behavior: `swift test` reports the same 116 tests passing before and after, by name.
Plan: one commit, mechanical, no test edits. Moves only.

## Remote editing leaves `FileActions`  [Worth exploring]

Files: `Sources/Pane/FileActions.swift` (553 lines)
Signal: a file past 500 lines and a type with 7 stored properties for features that do not share state (the clipboard and undo on one side, remote copies and their sync loop on the other).
Problem: S-066 added `edits`, `statusMessage`, `pendingEditConflict`, the sync loop, and the quit hook to the type that also owns paste, undo, rename, and delete. `statusMessage` is shown by the Status bar for anything, but only remote editing sets it.
Proposal: `RemoteEditing` (an `@Observable` class like `Places`) owns the `RemoteEdits`, the poll loop, the conflict question, and the status message. `FileActions` keeps `openRemoteFile` as a one-line call.
Benefits: `FileActions` back near 440 lines; remote editing testable without the rest.
Proof of same behavior: the 14 S-066 checks; `remote-edit` snapshots.
Plan: one commit. Worth doing only if more remote-editing features follow in M7; today the cost is moderate and the file is under 600.

## Remote providers share boilerplate  [Speculative]

Files: `S3FileSystem`, `SFTPFileSystem`, `FTPFileSystem`
Problem: each repeats `trash` (throws "not supported"), `copy` (same), `exists` (one line calling `RemoteTree.exists`), `disconnect`.
Proposal: default implementations in a `RemoteFileSystem` extension.
Benefits: about 12 lines fewer. No behavior gain, and a default can hide a provider that forgot to implement something real.
Plan: skip unless a fourth provider is added.

## Considered, not recommended

- Replacing the system `sftp` and `curl` with a library or a hand-written FTP client: no signal. Speed on 10,000 files is not measured yet; measure it first ([manual] in S-062).
- Moving the remote providers to their own target: nothing else would use it.
- Splitting `Snapshot.swift` (304 lines) or `SelfTestRemote.swift` (525 lines): both are flat lists of independent pages and checks. Revisit past 600.

## Top recommendation

**Connecting to a server is one flow, not three** (Strong), in the four steps above, then **one test file per area** (Strong). Do both before M7: M7 (S-050 to S-054) does not touch connecting, so the cost of leaving it grows only when the next protocol or saved-connection field arrives, but each step here is small and keeps behavior the same.

## Done (2026-11-01)

- One test file per area: `FileOperationsTests`, `S3Tests`, `SFTPTests`, `FTPTests`, `TransferTests`, `ServerEditTests`, `SavedConnectionTests`, helpers in `TestSupport`. Same 116 tests before and after.
- One connect flow: `SecretStore` (Keychain and in-memory adapters) replaced nine closures. `ConnectionForm` in PaneKit checks the fields, with two unit tests (118 tests). One `connect(form)` serves FTP, SFTP, and S3; every provider has `start()`. The five connect snapshots and 291 self-test checks are unchanged. `Connections` went from 287 to 220 lines.
- `Connections` now owns the router and the saved-server opener. `connected`, `disconnect`, and `removeSavedConnection` stay in `AppModel` on purpose: they also move tabs and the tree, which `Connections` should not know about. `AppModel` is 364 lines (was 371).
