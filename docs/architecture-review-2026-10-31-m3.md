# Architecture review after M3, 2026-10-31

Check-in after M3 Views and tabs (8e48dd7), before M4 Find and inspect. 4,093
lines of Swift. Largest files: `SelfTest.swift` 389, `FileActions.swift` 321,
`FileOperations.swift` 278, `AppModel.swift` 212. No trigger from the "when to
run" list fired. The split before M3 did its job: tabs were an array of
`FolderTab` and a tab strip, with no change to the views.

The code is fine. Two things to watch:

## SelfTest.swift grows with every story  [Speculative]

389 lines, 100 checks, and a run of about four minutes because each step waits
for a listing. Not a design problem yet, but a slow check gets skipped.
Proposal: when it passes 500 lines, split it by milestone into one file per
section (`SelfTestBrowse`, `SelfTestFiles`, `SelfTestViews`) and replace fixed
sleeps with a wait-until helper (`await until { model.tab.items.count > 3 }`).
Proof: the same checks, a shorter run.

## Views that read the model from the environment  [Speculative]

Two crashes came from `@Environment(AppModel.self)` in views hosted outside the
view tree (Table cells, menus). Now fixed by passing the model in, and logged in
`docs/FIXLOG.md`. If a third appears, give every view the model as a plain
property and drop the environment key.

## Considered, not recommended

- Moving `ViewSettings` into `PaneKit`. It uses SwiftUI's column layout type.
- A `FolderTab` per window. Tabs live in one window by design (docs/DESIGN.md).
- Replacing `Table` with a custom list for the rubber band (S-028). That is a
  feature decision first. Revisit if the user wants it.
