# Architecture review after M4, 2026-10-31

Check-in after M4 Find and inspect (e78da4a), before M5 System. 5,037 lines of
Swift. Largest: `SelfTest.swift` 477, `FileActions.swift` 321, `FileOperations.swift`
278, `AppModel.swift` 271. The split before M3 held: M4 added a preview pane,
Properties, tags, Quick Look, and search without touching `FolderTab`'s shape.

## Make the self-test faster and steadier  [Strong]

Files: Sources/Pane/SelfTest.swift (477 lines, 126 checks)
Signal: it is 23 lines from the 500-line mark, a full run takes about four
minutes, and it flaked once on a fixed sleep (FIXLOG: "Space closes Quick Look").
A check that is slow or flaky gets skipped, and this one guards every story.
Problem: each step waits a fixed time (`Task.sleep`) for a listing or an
operation, whether it needs it or not, and a slow machine can still miss.
Proposal: a `wait(until:timeout:)` helper that polls every 50 ms and returns as
soon as the state is true, then split the file by milestone.

```swift
@MainActor func until(_ timeout: Double = 3, _ condition: () -> Bool) async -> Bool
// before: try? await Task.sleep(for: .seconds(1)); check("moved", ...)
// after:  check("moved", await until { fm.fileExists(atPath: dest.path) })
// files:  SelfTest+Browse.swift, +Files.swift, +Views.swift, +Find.swift
```

Benefits: the run drops to roughly a minute, flakes become real failures with a
timeout message, and each file stays under 200 lines.
Proof of same behavior: the same 126 checks pass before and after, and the suite
still fails when a feature is broken (try one deliberate break).
Plan, one commit per step: 1) add `until` and convert the sleeps in one section.
2) convert the rest. 3) split by milestone.

## AppModel collects small features  [Speculative]

271 lines: tabs, the Navigation pane, pins, tags, Properties, Quick Look, search
focus. Each is small. If M5 adds three more, move pins and tags into `QuickAccess`
and `TagActions` types, the way `FileActions` was split out.

## Considered, not recommended

- Passing the model to every view as a property. Two crashes came from the
  environment, but only inside Table cells and menus, and those are fixed.
- Moving the Spotlight adapter into `PaneKit`. It uses `NSMetadataQuery` and the
  main actor, so it belongs in the app.
