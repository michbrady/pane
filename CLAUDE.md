# Pane

A native macOS file manager in SwiftUI with a Windows 11 File Explorer layout, for people
switching from Windows. It has no database: it reads the file system, and browses FTP, SFTP,
and S3 servers as folders. Swift 6, macOS 26, `PaneKit` plus the app. Free, MIT, public repo `michbrady/pane`.

## Layout

- `Sources/Pane/` the app. `App.swift` has the window and menus. `AppModel.swift` holds navigation state. `Locations.swift` has the home folder and `Prefs`.
- `Sources/PaneKit/` rules and data logic with no SwiftUI. Tests in `Tests/PaneKitTests/`.
- `Package.swift` a Swift package. There is no Xcode project.
- `build.sh` builds, signs, and installs `~/Applications/Pane.app`.
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh`; `tools/icon_review.sh` renders every look into one PNG.
- `docs/` `BRIEF.md`, `STORIES.md` (the backlog: status of every story), `GLOSSARY.md` (one name per thing), `DESIGN.md`, `FIXLOG.md`, and `architecture-review-*.md`. `ARCHITECTURE.md` at the root maps the targets and seams.
- Tests in `Tests/PaneKitTests/`: one file per area, shared helpers in `TestSupport.swift`. `swift test` runs them.
- `release.sh` signs with Developer ID and notarizes.

## Build and check

- Build and install: `./build.sh`. Add `--open` to restart the app with the new build. The build shows warnings; fix them.
- Unit tests: `swift test --scratch-path ~/Library/Developer/Pane/test-build`.
- Self-test (the app's real functions on a throwaway home folder): `tools/selftest.sh`. It takes about 30 seconds. Run one at a time: the script waits for any earlier run to exit. Exit 0 when every check passes. Add a check for every story with logic in `SelfTest.swift`.
- After every UI change, take snapshots with sample data and look at them: `tools/snap.sh`.
  It writes `/tmp/Pane-shots/<page>-light.png` and `-dark.png` for every snapshot page (`Snapshot.Page`), and `settings-<tab>-light.png` and `-dark.png` for every Settings tab, then quits. `APP_SNAPSHOT_PAGES=window,settings tools/snap.sh` limits the pages.
  For a panel, sheet, or popover, add a capture to `Snapshot.swift` like the Settings loop.
- Snapshots and the self-test refuse to run without `APP_HOME` in /tmp. `tools/make-fixture.sh` builds that home folder.
- Never test against your real folders or settings. `APP_HOME` also switches to a throwaway settings suite.
- Then check the grid: `tools/grid-lint.sh` and `swift tools/check-layout.swift /tmp/Pane-shots/*-layout.json`. Both print PASS.
- A change is done when the build has no errors, the grid checks pass, and you looked at the light and dark snapshots.

## Things that bite

Each of these cost a debugging session. The full stories are in `docs/FIXLOG.md`.

- A remote place is a URL (`sftp://`, `ftp://`, `ftps://`, `s3://`). Never let one reach a local file call: go through `FileSystemRouter.filesystem(for:)`. `FileOperations` works on any `FileSystem`, so use it for rename, delete, and New Folder on both.
- Compare URLs by standardized path (`/tmp` vs `/private/tmp`, trailing slash), and select from the listing.
- Table cells and menus do not inherit `@Environment`: pass the model in.
- Read modifier keys synchronously in the event callback, never after an `await`.
- Test Pane's decisions, not desktop state. A check that depends on focus must clear it first (`NSApp.keyWindow?.makeFirstResponder(nil)`). Quick Look uses `isShown`.
- One self-test or snapshot run at a time, and only after "Build complete". A stuck run: `pgrep -fl Contents/MacOS/Pane`. Never overlap runs.
- Anything that makes quitting asynchronous must skip runs where `Locations.isOverridden`.
- Real system effects (Keychain, NetFS mount, global hotkey, Terminal, `sftp`, `curl`) sit behind a seam with a fake. Passwords never go in process arguments, and secrets live in the Keychain only (`SecretStore`).
- An `exists` check looks in the parent's listing, never at whether a broader call failed.

## Working rules

- Work story by story from `docs/STORIES.md` (`improve-loop`). At the end of a milestone run `improve-architecture` and write a review file.
- Add a FIXLOG entry for every bug, ending in a `Rule:` line.
- Commit messages end with the Co-Authored-By line from the session. Never push, upload, or notarize without being asked.
- Web pages for bradysbit.com/pane/ and the first release are still to do (copy Ripple's pipeline).

## Design rules

- Design rules: `design/DESIGN-SYSTEM.md`, layout in `docs/DESIGN.md`. Use its tokens; never raw colors, radii, or durations.
- Use Apple's controls and system styles. Only the accent color is custom: `UI/Theme.swift` (`ThemeStore.defaultID`). People change it, and light or dark mode, in Settings > Appearance.
- Views use `.tint`, `Palette.accent`, `Palette.accentText` (accent-colored text), and `Palette.onAccent` (text on an accent fill). Never hard-code colors, radii, or durations in views.
- Compare accents: add `APP_ACCENT=<id>` to the snapshot command.
- Spacing comes from `Space` in `UI/Grid.swift`, on a 4 pt grid. Mark custom pages and cards with `.gridArea` and `.gridProbe`.
- Windows open calm: `.noInitialFocus()` on every window and sheet (no focus ring or selected text on open), `.fitsContent()` on sheets and Settings tabs (no scroll bar with nothing to scroll). System scroll bars. Both in `UI/WindowBehavior.swift`.
- Settings: one tab per topic in `SettingsView.swift`, one grouped Form per tab. Add a case to `SettingsTab` for a new tab.
- Window chrome (title bar, toolbar, sidebar, menus, sheets) stays system. Buttons use system styles, like `.borderedProminent`.
- Colors: `.primary`, `.secondary`, `.tint`, and system colors. Never fixed grays or white for text.
- Every action has a menu bar item and a keyboard shortcut.
- `Label` for icon and text pairs. SF Symbols for icons.
- `ContentUnavailableView` for empty states.
- Liquid Glass belongs to floating controls only, never to content.

## Skills

The bama plugin has a skill for each step: `mac-design` (design rules),
`design-system` (accent and tokens), `layout-grid`, `ux-design`,
`swift-swiftui`, `os-integrations`, `performance`, `build-and-verify`,
`test-mac-app`, `app-icon`, `user-stories`, and `improve-loop`. Use them.

## Git

- Commit after each working change, with a message that says what the user can now do.
