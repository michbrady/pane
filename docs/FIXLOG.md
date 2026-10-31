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
