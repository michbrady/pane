# Explorer-style file manager for the Mac

Research for Pane. Done 2026-10-31.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.

Question: what does a Windows-Explorer-style Finder replacement need in
version one, and which macOS APIs make it possible?

Coverage note: every track ran only a handful of searches. No App Store
review text, Hacker News threads, or Reddit threads were read directly, and
no pixel measurements were taken. Treat [K] and [U] as work to do.

## Findings

Market
- Mature Finder alternatives (ForkLift, Path Finder, Commander One, Marta,
  Nimble Commander, Double Commander) all use the dual-pane Commander model.
  None is described as Explorer-style. [V]
- Explorer-style apps exist but are free or early: Win Finder (v0.3.0, no
  tree, no tabs) [V https://skimmenthal13.github.io/winfinder/], Explorer for
  Mac by Binary Quest (tabs, tree, breadcrumbs, Quick Look, tags) [V
  https://alternativeto.net/software/explorer-for-mac/about/], Folders File
  Manager (tree plus files, breadcrumb dropdowns) [V
  https://apps.apple.com/us/app/id1593644229], FileNav (tree, Windows
  switchers) [V https://alternativeto.net/software/filenav/about].
- No source shows a polished, paid, maintained app that copies the full
  Explorer UI. [U] Absence of evidence only.
- No app was found with an Explorer command bar, Quick access section, or
  Explorer-style preview pane. [U]

Windows habits that Finder breaks
- Cut does not move. The workaround is Cmd+C, then Cmd+Option+V. [V
  https://support.apple.com/en-au/102323]
- Return renames instead of opening. Open is Cmd+O or Cmd+Down. [V same]
- Delete needs Cmd+Delete. [V same]
- No editable address bar (path bar is read-only, Cmd+Shift+G is a dialog),
  no Alt+Up, no tree sidebar, folders-first off by default. [K]

Windows 11 layout [K, third-party sources]
- Title bar with tabs, address bar with search box, icon-only command bar,
  navigation tree on the left, content area, optional preview or details
  pane on the right, status bar.
- Tabs: Ctrl+T, Ctrl+W, Ctrl+Tab, Ctrl+1-9. [V
  https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec]
- Drag rules: Ctrl copies, Shift moves, Alt makes a shortcut. [V same]

Platform
- A third party cannot remove Finder. It can take over folder opens and
  reveal-in-file-viewer calls. Finder keeps the Desktop, Trash UI, AirDrop,
  Put Back, Services. [K]
- Folder handler method: `defaults write NSGlobalDomain NSFileViewer` plus a
  `public.folder` `LSHandlers` entry. Reports are inconsistent across
  reboots. [V https://talk.macpowerusers.com/t/forklift-3-default-file-viewer-with-mac-os-catalina-10-15-7/33989]
- Path Finder redirects other apps' "Reveal in Finder". [V
  https://www.stclairsoft.com/blog/?p=2000]
- `NSWorkspace.activateFileViewerSelecting` activates Finder. [V
  https://developer.apple.com/documentation/appkit/nsworkspace/activatefileviewerselecting(_:)]
- A Mac App Store build is not viable (sandbox blocks path access, Full Disk
  Access, spawning tools). Ship Developer ID, notarized, not sandboxed, with
  Full Disk Access granted by the user. [K]
- Use `NSTableView` and `NSOutlineView` through `NSViewRepresentable` for the
  list and tree. SwiftUI `OutlineGroup` builds the tree eagerly. [K]
- FSEvents for tree watching. Poll network volumes. iCloud uses placeholder
  files. [K]

## Likes and dislikes
| App | People like | People dislike | Sources |
| --- | --- | --- | --- |
| Path Finder | Batch rename, big preview pane, dual pane, deep customization, integrated terminal | $29.95/yr subscription "not worth that much", buggy updates, folders showing empty in v7.x, slow support, scripts and Keyboard Maestro differ from Finder | https://talk.macpowerusers.com/t/does-anybody-still-use-path-finder-from-cocoatech/28350, https://talk.tidbits.com/t/path-finder-26-0/33442 |
| ForkLift | Fast, fewer bugs than Path Finder, FTP and cloud, dual pane | Seen as an FTP client more than a Finder replacement, dense power-user UI [K] | same macpowerusers thread, https://alternativeto.net/software/forklift/?p=2 |
| Commander One | Lightweight, cloud and FTP, Spotlight search, free tier | No sidebar so navigation is clumsy, no preview pane, dated look [K] | macpowerusers thread, https://forums.macrumors.com/threads/best-finder-alternatives-file-managers.2258057/ |
| Marta | Fast, light on CPU and RAM | Maintenance unclear (v0.8.2, footer 2016-2024), NAS problems for one user, config-file driven [K] | macpowerusers thread, https://marta.sh/ |
| Nimble Commander | Free, open source, built-in terminal, batch rename | Not researched [U] | https://magnumbytes.com/ |
| Double Commander | Free, Total Commander plugins, multi-rename | Cross-platform so not native [K] | https://doublecmd.sourceforge.io/ |
| XtraFinder / TotalFinder | Add tabs and dual pane to Finder [K] | TotalFinder discontinued 2021, needs SIP changes on Tahoe | https://discuss.binaryage.com/t/there-has-to-be-one-little-thing-missing-to-get-totalfinder-working-in-sequoia-and-tahoe/11092/4 |
| Finder | Quick Look, tags, Spotlight, Smart Folders, column view, best in class per Mac users | Cut does not move, Return renames, no address bar, no tree, large moves choke [U] | https://applevis.com/comment/188444, https://macmost.com/questions-new-mac-users-have-when-switching-from-windows.html |
| Windows Explorer | Better for manipulating files, search bar at top, connected network drives listed | Mac users' complaints are weakly sourced: ads, slow search, Quick Access noise [U] | https://redlib.hyperreal.coffee/r/MacOS/comments/1ht47jy/is_windows_file_explorer_better_than_apple_finder |

Patterns:
- Must have (loved or missed repeatedly): real cut and move, Quick Look,
  tags, Spotlight search, network and cloud access, speed.
- Our chance (disliked repeatedly): Path Finder's bugs and subscription,
  Commander One's missing sidebar, dual-pane complexity for casual users, no
  app that targets Explorer habits.

## Feature matrix
| Feature | Explorer | Finder | Path Finder | Version one? |
| --- | --- | --- | --- | --- |
| Tree navigation pane | Y | No | Y | Yes |
| Quick access / favorites | Y | Sidebar | Bookmarks bar | Yes |
| Editable address bar with breadcrumbs | Y | No | Y | Yes |
| Back / forward / up | Y | Y | Y | Yes |
| Details view, sortable columns | Y | List | Y | Yes |
| Icons, list, tiles | Y | Icons, list, columns, gallery | Y | Icons and list, tiles later |
| Tabs | Y | Y | Y | Yes |
| Search box in the top bar | Y | Y (Spotlight) | Y | Yes |
| Preview / details pane | Y | Y | Y | Yes, plus Quick Look |
| Command bar | Y | Toolbar | Toolbar | Yes |
| Cut, copy, paste (real move) | Y | Move via Cmd+Option+V | Y | Yes, signature feature |
| Copy dialog with conflict handling | Y | Basic | Own engine | Yes |
| Undo file operations | Y | Y | [U] | Yes |
| F2 rename, Return opens | Y | Return renames | Y | Yes |
| Delete key to Trash | Y | Cmd+Delete | Y | Yes |
| Folders first | Y | Option | Y | Yes, on by default |
| Show extensions and hidden | Y | Y | Y | Yes |
| Tags | Weak | Y | Y | Yes |
| Network and cloud (SMB, iCloud) | Y | Y | Y | Yes, basic |
| Zip browse and extract | Y | Extract only | [U] | Later |
| Properties / Get Info | Y | Y | Y | Yes, custom panel |
| Batch rename | Basic | Y | Y | Later |
| Dual pane, Drop Stack | No | No | Y | Later |
| FTP, SFTP, S3 | No | No | Partial | Later |

## Decisions
1. Target the Explorer metaphor for people switching, not a power-user
   Commander. The gap is real but unproven. Planned test: use Explorer for
   Mac, Folders, and Win Finder for an hour each and list what each lacks.
2. Use the Windows 11 layout: title-bar tabs, address bar with search,
   icon-only command bar, tree, details view, status bar. Take Mac chrome
   (sidebar, toolbar, Liquid Glass, system fonts) rather than custom chrome,
   because Design [K] found this keeps Explorer's layout. Planned test:
   mock the window and compare with an Explorer screenshot.
3. Build real Cut and Paste as the signature feature, because Cut does not
   move files in Finder [V]. Planned test: cut in one tab, paste in another,
   across volumes, with undo.
4. Map Ctrl to Cmd. Keep F2, F3, F4, F5. Add Return as open and F2 as rename
   as a setting. Avoid Option+letter shortcuts, because they type
   characters [K]. Planned test: walk the shortcut table in the design notes
   and mark each clash.
5. Settle four collisions in the brief: the Delete key, Cmd+1-9 (tabs vs
   Finder view modes), Cmd+Shift+3-5 (screenshots), F11 (Show Desktop).
6. Keep Quick Look (spacebar), tags, and Spotlight search, because both
   Mac and Windows users praise them [V].
7. Ship outside the Mac App Store: Developer ID, notarized, not sandboxed,
   with Full Disk Access [K]. Planned test: browse Desktop, Documents,
   external volumes, and iCloud with and without Full Disk Access.
8. Use `NSOutlineView` and `NSTableView` for the tree and list, SwiftUI for
   chrome [K]. Planned test: open a 100,000-file folder and measure hangs.
9. Take over folder opens with `NSFileViewer` and `public.folder`, and ship
   Pane as a Finder companion first, because Finder cannot be removed [K].
   Planned test: [U] below.
10. Price against Path Finder's $29.95 a year subscription [V]. Prefer a
    one-time price. Verify ForkLift and Commander One prices first.

## Open questions
- Does `NSFileViewer` still work on macOS 26, and does `LSHandlers` survive a
  Launch Services rebuild? Test: set it, reboot, run
  `lsregister -kill -r -domain local -domain user`, then reveal a file from
  another app.
- Do Put Back and the Trash UI work for files Pane trashes? Test: trash with
  `FileManager.trashItem`, then Put Back in Finder.
- How does `OutlineGroup` perform at 100,000 files on macOS 26? Test: a probe
  app with a generated folder.
- Do ForkLift and Path Finder support macOS 26? Check their release notes.
- Is Marta still maintained? Check the repository and release dates.
- Is dual pane wanted, or is a single Explorer-style pane enough? Test with
  five Windows switchers.
- Exact Explorer pixel sizes, column widths, and checkbox hover behavior.
  Test: screenshot Explorer on Windows 11 and measure.
- What do Mac users dislike in Explorer? Sourced only by guesses. Search
  Reddit and Hacker News.
- Prices for ForkLift, Commander One, and Folders File Manager.
- Can Pane replace "Show in Finder" for apps that use Apple Events? Test:
  reveal from Xcode, Mail, and Safari downloads.
