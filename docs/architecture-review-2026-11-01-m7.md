# Architecture check-in after M7 (polish)

Survey of 2026-11-01. M7 added context menus, the Advanced tab with the Return key choice, F6 focus, and VoiceOver labels. 5 stories.

## Reading

| Signal | Reading |
| --- | --- |
| Biggest files | `FileActions` 553, `SelfTestRemote` 520, `AppModel` 389 (was 364), `FolderTab` 345, `DetailsView` 305 |
| Pure rules added | `ContextMenuPlan`, `FocusCycle`, `ItemSpeech`, all in `PaneKit` with unit tests (121 tests) |
| Seams | none new. Real focus and real menus stay untested by design (desktop state). |

M7 put the new rules in `PaneKit` first and kept the views thin, which is why 8 of its checks run in `swift test` and not in the app.

## Remote editing leaves `FileActions`  [Worth exploring]

Same card as the M6 review. `FileActions` is still 553 lines, and M7 did not add to it, so the case has not got stronger. Do it when remote editing changes again.

## `AppModel` grows a little each milestone  [Worth exploring]

`AppModel` went 307, 371, 364, 389. M7 added `moveFocus` and `pressReturn`, both small. The focus code is the only part with its own state (`focusRegion`, `listFocusRequests`) and could join `FocusMover` as a small `KeyboardFocus` object. At 389 lines, below the 600 line trigger, this is not urgent.

## Considered, not recommended

- Replacing the SwiftUI context menu with an AppKit `NSMenu` now. Wait for the manual check of Services and the icon row first: if both look right, there is nothing to do.
- Splitting `SelfTestRemote.swift` (520 lines, flat list of checks). Revisit past 600.

## Top recommendation

Nothing is Strong. The code is fine for what is left: S-028, the web pages, and the first release. Re-run this check after any large feature.
