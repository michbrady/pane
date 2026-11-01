# Fix log

## Folder URLs compared unequal (M1, M2)
Symptom: `open([folder])` did nothing, and a test's selection cleared itself.
Cause: the same folder has several spellings: a trailing slash or not, and `/tmp` or `/private/tmp`. `URL` equality sees them as different.
Fix: `AppModel.canonical(_:)` for folders, comparing by `standardizedFileURL.path` in `open`, and selecting from the listing in tests.
Rule: compare file URLs by standardized path, and take selections from the listing, never from hand-built URLs.

## One Undo reversed several changes (S-014)
Symptom: Undo after a Trash also undid earlier copies, and Redo named the wrong action.
Cause: `UndoManager` groups every change made in one run loop pass. Pane's changes finish in background tasks, so several shared one group.
Fix: `registerUndo` closes any open group and wraps each change in its own group.
Rule: wrap every undo registration for a finished operation in its own `beginUndoGrouping` and `endUndoGrouping`. Leave `groupsByEvent` on, because text fields need it.

## Selection after Trash came back empty (S-013)
Symptom: the item that moved up was not selected.
Cause: the folder watcher reloaded as soon as the move began, listing the folder before the item was gone and using up the request. The Table also drops its selection while it swaps rows.
Fix: keep the request until a listing without the removed items arrives, then select after 80 ms.
Rule: after a change that removes rows, wait for a listing that shows the change before choosing a new selection.

## Rows could not be dragged (S-017, found after M2)
Symptom: dropping onto folders in the Navigation pane worked in code, but dragging a row did nothing.
Cause: a SwiftUI `Table` row is a drag source only through `TableRow(...).draggable(...)`. The `dragContainer` I used alone adds no source.
Fix: `Table(of:)` with `TableRow(item).draggable(item.url)`. A drag from this window uses the selected rows to choose move or copy.
Rule: never mark a drag feature done from model-level tests alone. Prove the gesture with a real drag, with Pane frontmost.
Status: proven with `tools/drag-test.sh`, a real mouse drag: a row dropped on a tree folder moves, and Option-drop copies.

## Option was read after the files loaded (S-017)
Symptom: found by the real drag. An Option-drop moved instead of copying.
Cause: `performDrop` loaded the dropped files asynchronously and read the modifier keys afterwards, when Option could already be released.
Fix: read `NSEvent.modifierFlags` at the instant of the drop and pass the keys to `drop(_:into:option:command:)`.
Rule: read keyboard modifiers synchronously in the event callback, before any `await`.

## Table cells and menus crashed on `@Environment(AppModel.self)` (S-023)
Symptom: the app crashed with "No Observable object of type AppModel found" as soon as a folder opened.
Cause: new views read the model from the SwiftUI environment, but Table cells and context menus are hosted outside it.
Fix: `NameCell`, `RenameField`, and `ItemMenu` take the model as a plain property.
Rule: a view that lives in a Table column or a menu gets its model passed in. Use `@Environment(AppModel.self)` only for views in the normal view tree.

## The preview spun forever on an image that would not load (S-031)
Symptom: selecting a damaged or fake image showed a spinner in the preview pane that never stopped.
Cause: the pane showed a spinner while the image was nil, and nil also meant "loading finished and failed".
Fix: a `failed` flag, set when loading ends with nothing, shows the file's icon instead.
Rule: a loading state needs an end state for failure. Never use "no value yet" to mean both "loading" and "gave up".

## Quick Look's visibility is up to the desktop, so a check on it was flaky (S-032)
Symptom: "Space closes Quick Look" failed in some full runs and passed in others, and failed every time once the test tried to activate the app.
Cause: macOS hides a panel while its app is not in front, and refuses to bring a background app forward on request. The check read `panel.isVisible`, which depends on what the desktop is doing.
Fix: `QuickLookController.isShown` tracks whether Pane opened the panel, and clears when the panel closes. The check tests that, and the real panel is tried by hand.
Rule: in the self-test, check what Pane decided, not whether macOS drew a window. Leave on-screen behavior to the hand-test list.

## Self-test runs overlapped and corrupted each other (S-030 run)
Symptom: occasional runs stalled or failed from the conflict section on, while the next run passed.
Cause: a run started while an earlier Pane was still shutting down, and both used the same throwaway folder and settings.
Fix: `tools/selftest.sh` waits for any running Pane to exit before it starts.
Rule: run the self-test one at a time. Never start a second run while one may still be going.


## Going into a server's folder snapped back to the server's top (S-060)
Symptom: found by the self-test. Opening a folder on a server, or typing `sftp://nas/Docs` from a local folder, ended up at `sftp://nas/`.
Cause: the tree selects the server's row, and a selection change navigates to the row's folder. The server's row means its top.
Fix: the tree does not navigate when the selected row is the server the tab is already inside.
Rule: a tree row that stands for a whole place must not act as a "go to" when the tab is already somewhere inside it.

## The lost-connection screen also told people to allow Full Disk Access (S-060)
Symptom: found in a snapshot. Under the correct "Connection lost. Reconnect" banner, a second overlay said "Pane needs Full Disk Access".
Cause: the generic error overlay showed for any load error, and its text is about permissions on this Mac.
Fix: a lost connection shows only the banner over the dimmed list, and errors from a server show their own words.
Rule: every error state has its own words. A generic overlay must name what it is for.

## A server's row could list this Mac's folders (S-060)
Symptom: found in a snapshot: the server row had an expand arrow.
Cause: listing the server's URL as a local path read this Mac's root folder.
Fix: rows for servers never list folders in the tree.
Rule: a remote URL must never reach a local file call. Check both the call and what it would show.

## A snapshot taken while another run was alive showed an empty, inactive window (S-063)
Symptom: the S3 snapshot had gray traffic lights, no sidebar, and no sheet.
Cause: a failed build left a snapshot run waiting, and a second run started on top of it. My `pkill` pattern needed an argument that snapshot runs do not have, so it killed nothing.
Fix: find the old run with `pgrep -f Contents/MacOS/Pane`, end it, then start one run and read its fresh files.
Rule: one snapshot or self-test run at a time. Check the build printed "Build complete" before running, and check the PNG is the key window before judging it.

## The self-test failed once on "Rename lights up" and passed on the next run (S-061)
Symptom: one failure in 243 checks, gone on a re-run, with no change near it.
Cause: Rename and the edit keys step aside while a text field has focus, which is right for the app. The check assumed no field had focus, and the window's first responder is up to the desktop at launch.
Fix: the check clears the first responder before it looks.
Rule: a check about what the app decides must set up every input that decision reads, including which control has focus.

## `exists` said yes to any name on a server (S-065)
Symptom: found while planning New Folder on S3: `FileOperations.makeFolder` asks `exists` for "New folder", "New folder (2)", and so on, until one is free.
Cause: the server file systems answered `exists` with "listing it did not throw". S3 lists a name that is not there as an empty folder, so every name looked taken and the loop would never end.
Fix: `exists` looks for the name in its parent's listing. A unit test lists an empty bucket and expects "not there".
Rule: a question about one thing is answered by looking at that thing's own record, never by whether a broader call failed.
