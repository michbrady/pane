# Architecture review, 2026-10-31

Check-in after M1 Browse (846975d), before M2 Move files. 1,891 lines of
Swift, largest file `AppModel.swift` at 237 lines. No signal from the
"when to run" list fired except "before a big feature". The code is fine.
One decision matters before M2.

## File operations as a module in PaneKit  [Worth exploring]

Files: none yet. M2 adds `S-010` to `S-017`. M6 adds FTP, SFTP, S3 (`S-060` to `S-066`).
Signal: before a big feature. Ask: what code change makes M2 easy, and M6 possible?
Problem: Copy, move, trash, rename, and undo will each need to work on a
local folder now and a remote place in M6. If they start inside `AppModel`
with `FileManager` calls, M6 has to rewrite them and tests cannot run
without the app target.
Proposal: a plain `FileOperations` type in `PaneKit` that takes a
`FileSystem` seam. Two adapters from the start (`LocalFileSystem`, and
`FakeFileSystem` for tests), so the seam is real. M6 adds three more.

```swift
public protocol FileSystem: Sendable {
    func list(_ folder: URL) async throws -> [FolderItem]
    func copy(_ source: URL, to destination: URL) async throws
    func move(_ source: URL, to destination: URL) async throws
    func trash(_ url: URL) async throws -> URL?   // nil: no Trash, delete asks first
    func makeFolder(_ url: URL) async throws
    func rename(_ url: URL, to name: String) async throws -> URL
}
public struct FileOperations {   // conflicts, batches, progress, undo records
    public func paste(_ items: [URL], into: URL, mode: .copy | .move, resolve: ConflictResolver) async throws -> OperationRecord
}
```

Benefits: Locality (conflict rules and undo live in one place). Leverage
(the conflict sheet, progress sheet, and Undo work for every provider in
M6). Tests cover conflicts, cross-volume moves, and undo with no UI.
Proof of same behavior: the M1 self-test (15 checks) and `PaneKitTests`
must keep passing. New tests for each story go in `PaneKitTests`.
Plan: build it as part of S-010 (copy) rather than as a refactor. There is
no old code to move. `FolderLister` becomes `LocalFileSystem.list`.

Not done now: it is a design for work that has not started, so there is
nothing to refactor. Build it in M2.

## AppModel holds navigation, listing, tree, and address state  [Speculative]

Files: Sources/Pane/AppModel.swift (237 lines)
Signal: none yet. Watch at 400 lines or when M3 tabs arrive.
Problem: Tabs (`S-026`) need one history, listing, and selection per tab.
Today there is one of each on `AppModel`.
Proposal: split a `FolderTab` type (history, items, selection, load state)
out of `AppModel` when S-026 starts. Keep `AppModel` for app-wide state.
Benefits: tabs become instances, not a rewrite.
Proof: self-test and snapshots.
Plan: do it at the start of S-026, not before.

## Pure tree logic inside AppModel  [Speculative]

Files: AppModel.swift `syncTree`, `url(forNavID:)`
Problem: Which folders expand, and which row selects, is pure logic that
sits in an observable class, so tests need the app target.
Proposal: `NavigationTree.expansion(for:home:)` in `PaneKit`.
Benefits: unit tests for the Home and volume cases.
Plan: one commit when the tree changes again (S-025, S-044, S-048).

## Top recommendation

Build `FileSystem` and `FileOperations` in `PaneKit` with S-010. It is not
`Strong`, because there is no code to refactor, so no refactor is done now.

## Considered, not recommended

- A `RemoteFileSystem` protocol now. One adapter (none yet) is a
  hypothetical seam. The local and fake adapters in M2 make it real.
- Splitting `AppModel` before tabs. It is 237 lines and reads well.
- Moving `NavNode` into `PaneKit`. It is small and only the app uses it.
