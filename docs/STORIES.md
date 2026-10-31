# Pane stories

Snapshot pages (named for `Screens:`): `window` (default window), `details`
(Details view), `tree`, `tabs`, `conflict` (copy conflict sheet),
`properties`, `preview`, `connect` (Connect to Server), `search`, `context-menu`, `settings`,
`onboarding` (Full Disk Access), `empty-folder`.

Decisions (agent): Cmd+1-9 go to tab N. View modes are Ctrl+Cmd+1/2/3.
Cmd+Shift+3-5 and F11 are not bound. Delete and Cmd+Delete both trash.
Backspace does nothing. Return opens, F2 renames. SMB and cloud storage are in version one (M5). FTP, SFTP, S3 wait on a user decision.

## M1 Browse

### S-001 Open the Pane window
As the user, I launch Pane and see a window with a tree on the left, a file list on the right, an address bar, and a status bar.
Screens: window
Acceptance:
- [snap] The window shows sidebar, address bar with search box, command bar, content, status bar.
- [snap] Light and dark look right with the system accent color.
UX:
- Flow: launch Pane, or Cmd+N -> window opens at the last folder (first run: Downloads) -> tree, Address bar, list and Status bar all show -> Cmd+W closes
- Surface: main window with sidebar layout (a place people come back to)
- States: empty folder shows "This folder is empty"; loading shows nothing under half a second, then a spinner row "Loading…"; error "Unable to read this folder. Pane needs Full Disk Access." with an "Open Settings" button
- Words: window title is the current folder name; Search box placeholder "Search"; tooltips on Command bar icons, for example "Copy the selected items (⌘C)"
- Access: F6 cycles Navigation pane, list, Address bar; VoiceOver reads "Navigation pane", "Item list", "Address bar"
Note: the Command bar and Search box show in place but stay dimmed until S-041 and S-030.
Status: done

### S-002 List a folder in Details view
As the user, I see a folder's files with Name, Date modified, Type and Size columns.
Screens: details
Depends: S-001
Acceptance:
- [unit] A folder with 1,000 files lists in under one second.
- [snap] Folders show before files, sizes read "4 KB", dates read like "10/31/2026 2:14 PM".
- [self] A file added from outside appears within two seconds.
UX:
- Flow: choose a folder -> rows appear folders first -> click selects -> double-click or Return opens -> new files appear without refresh
- Surface: inline in the content area (Details view); no modal
- States: empty "This folder is empty"; loading "Loading…" after half a second; error "Unable to read this folder." under the header with "Open Settings"; too much: long names truncate in the middle with the full name in a tooltip, and 100,000 rows scroll smoothly
- Words: columns "Name", "Date modified", "Type", "Size"; sizes "4 KB"; folders show "—" for Size
- Access: arrow keys move selection; VoiceOver reads "name, kind, size, date modified"
Status: done

### S-003 Open a folder or file
As the user, I select an item and press Return, or double-click, to open it.
Screens: details
Depends: S-002
Acceptance:
- [self] Return on a folder shows its contents. Return on a file opens it in its default app.
- [self] Cmd+Down opens too.
UX:
- Flow: select -> Return, Cmd+Down or double-click -> folder shows, or the file opens in its default app -> Cmd+[ goes back
- Surface: inline (changes the folder on screen, or hands off to another app)
- States: a file with no app shows an alert "No app can open this file." with "Choose App…" and "Cancel"; a locked folder shows the error state of S-002
- Words: context menu "Open"; Return opens, F2 renames (a setting can swap them later)
- Access: Return and Cmd+Down work from the keyboard alone; VoiceOver announces the new folder name
Note: Return, Cmd+Down and double-click are wired. Try them by hand [manual]: the self-test calls open() directly.
Status: done

### S-004 Go back, forward, and up
As the user, I click Back, Forward, Up or press Cmd+[, Cmd+] and Cmd+Up to move through folders.
Screens: window
Depends: S-003
Acceptance:
- [unit] History keeps order. Back then a new folder clears Forward.
- [self] Cmd+Up goes to the parent. At the root, Up is disabled.
- [snap] Disabled buttons look dimmed.
UX:
- Flow: Back, Forward or Up buttons, Cmd+[, Cmd+], Cmd+Up, or mouse back and forward buttons -> the list shows that folder -> a new folder after Back clears Forward
- Surface: inline Command-bar-style buttons at the left of the Address bar
- States: Back, Forward and Up are dimmed when unavailable; at the root, Up is dimmed
- Words: tooltips "Go back to the previous folder (⌘[)", "Go forward (⌘])", "Go up to the parent folder (⌘↑)"; menu items "Back", "Forward", "Enclosing Folder" under Go
- Access: all three work from the keyboard; VoiceOver reads "Go back, dimmed"
Status: done

### S-005 Type a path in the address bar
As the user, I click the address bar, or press F4 or Cmd+L, type a path, and press Return to go there.
Screens: window
Depends: S-003
Acceptance:
- [self] The bar turns into a text field with the path selected. Escape restores breadcrumbs.
- [unit] `~`, `~/Documents`, and spaces in paths resolve. A bad path shows an inline error and stays.
- [snap] Breadcrumbs show chevrons between folders.
UX:
- Flow: click the empty part of the Address bar, F4 or Cmd+L -> breadcrumbs become a text field with the path selected -> type, Return goes -> Escape or clicking away restores breadcrumbs
- Surface: inline in the Address bar (changes one value on screen)
- States: bad path keeps the field open with the message "No folder at this path." under it in red text and an icon; `~` and paths with spaces work; too much: long paths scroll
- Words: field label "Address"; tooltip on empty space "Type a path (⌘L)"
- Access: Return goes, Escape cancels; VoiceOver "Address, text field"
Note: F4 and Cmd+L start editing. Try them by hand [manual].
Status: done

### S-006 Click breadcrumbs
As the user, I click a folder in the breadcrumbs to jump there, and click a chevron to see its sibling folders.
Screens: window
Depends: S-005
Acceptance:
- [self] Clicking "Documents" in `Users > me > Documents > Work` goes to Documents.
- [self] A chevron menu lists subfolders and picks one.
UX:
- Flow: click a breadcrumb -> go to that folder; click the chevron after it -> menu of its subfolders -> pick one to go there; Escape closes the menu
- Surface: popover-style menu from the chevron (a few related choices tied to one control)
- States: a folder with no subfolders shows "No Folders" dimmed in the menu; the menu lists at most 30 with "Show All…" for more
- Words: tooltip on a breadcrumb "Go to Documents"; chevron "Show folders inside Documents"
- Access: keyboard focus reaches breadcrumbs with F6; VoiceOver reads "Documents, button" and "Show folders inside Documents, menu button"
Note: the chevron menu lists up to 30 folders. A "Show All…" item is not built.
Status: done

### S-007 Browse with the folder tree
As the user, I expand folders in the tree and click one to show it.
Screens: tree
Depends: S-002
Acceptance:
- [unit] Expanding loads children lazily. A folder with 10,000 children does not hang.
- [snap] The tree shows Quick access, This Mac (home, Desktop, Documents, Downloads, volumes) with disclosure arrows.
- [self] Left and Right arrows collapse and expand. The tree follows the current folder.
UX:
- Flow: click a disclosure arrow -> children load -> click a folder -> list shows it and the tree highlights it; Left and Right arrows collapse and expand
- Surface: Navigation pane sidebar (a place people come back to)
- States: empty folder shows no arrow; loading shows a small spinner beside the arrow; error shows a lock icon with tooltip "Pane can't read this folder."; too much: only visible rows render
- Words: sections "Quick access" and "This Mac"; tooltips on arrows "Show folders inside Downloads"
- Access: arrow keys move and expand; VoiceOver reads "Downloads, collapsed, 1 of 6"
Note: Left and Right arrow expand and collapse, and a 10,000-folder tree load, still need a hand test [manual].
Status: done

### S-008 Remember my window and folder
As the user, I quit and reopen Pane and find the same folder, window size, and expanded tree.
Depends: S-007
Acceptance:
- [unit] State saves and loads from the settings store.
- [self] Relaunch restores folder, window frame, tree expansion.
UX:
- Flow: quit Pane -> reopen -> same folder, window size, and expanded tree appear with no prompt
- Surface: none (no screen, state restore)
- States: if the saved folder is gone, open Downloads and show no error; if settings are unreadable, start fresh and show nothing
- Words: none
- Access: nothing new
Note: the folder and expanded tree restore. Window frame uses frame autosave. Try a relaunch by hand [manual].
Status: done

## M2 Move files

### S-010 Copy and paste files
As the user, I select files, press Cmd+C, go to another folder and press Cmd+V to copy them.
Depends: S-003
Acceptance:
- [unit] Copying a folder copies its contents and keeps dates.
- [self] A progress sheet shows for operations over one second.
Status: todo

### S-011 Cut and paste to move
As the user, I press Cmd+X on files and Cmd+V elsewhere to move them.
Depends: S-010
Acceptance:
- [unit] Cut items stay until paste. Pressing Escape or copying something else clears cut.
- [unit] Moving across volumes copies then removes the original only after success.
- [snap] Cut items show faded in the list.
Status: todo

### S-012 Resolve name conflicts
As the user, when a pasted file's name exists, I choose Replace, Skip, or Let me decide.
Screens: conflict
Depends: S-010
Acceptance:
- [snap] The sheet shows both files with size and date, and Replace, Skip, Decide choices.
- [unit] "Do this for all" applies to the rest of the batch.
- [unit] Skip leaves both files untouched. Replace never loses the original if the copy fails.
Status: todo

### S-013 Delete to the Trash
As the user, I press Delete or Cmd+Delete to trash the selection.
Depends: S-002
Acceptance:
- [unit] Files move to the Trash through `trashItem`.
- [self] Both keys work. Shift+Delete asks first, then deletes for good.
- [self] Selection moves to the next item.
Status: todo

### S-014 Undo file operations
As the user, I press Cmd+Z to undo a move, copy, rename, new folder, or trash.
Depends: S-013
Acceptance:
- [unit] Each operation registers its inverse. Undo of trash restores the original path.
- [self] Edit menu names the action: "Undo Move 3 Items".
Status: todo

### S-015 Rename with F2
As the user, I press F2 (or click a selected name) and type a new name.
Depends: S-002
Acceptance:
- [self] The name field edits in place with the base name selected, not the extension.
- [unit] A clashing name shows an error and keeps editing.
- [self] Return does not rename. It opens (S-003) unless editing.
Status: todo

### S-016 Create a new folder
As the user, I press Cmd+Shift+N to add "New folder" and rename it right away.
Depends: S-015
Acceptance:
- [unit] Names go "New folder", "New folder (2)".
- [self] The new row is selected and editing.
Status: todo

### S-017 Drag files with Windows rules
As the user, I drag files to move on the same volume and copy across volumes, with Option to copy and Cmd to move.
Depends: S-011
Acceptance:
- [unit] No modifier: same volume moves, other volume copies.
- [self] The cursor shows a plus badge for copy.
- [self] Dropping on a tree folder or tab works.
Status: todo

## M3 Views and tabs

### S-020 Sort by clicking a column
As the user, I click a column header to sort, and click again to reverse.
Screens: details
Depends: S-002
Acceptance:
- [snap] The header shows an arrow for the sort direction.
- [unit] Name sorts naturally ("file2" before "file10"). Size sorts by bytes.
Status: todo

### S-021 Keep folders first
As the user, I see folders above files by default, and can turn it off in Settings.
Depends: S-020
Acceptance:
- [unit] Folders sort first for every column.
- [self] The setting applies at once.
Status: todo

### S-022 Choose and resize columns
As the user, I right-click a header to add or hide columns and drag edges to resize.
Depends: S-020
Acceptance:
- [self] Date created, Kind and Tags can be added.
- [unit] Widths and order save per folder.
- [self] Double-clicking an edge fits to content.
Status: todo

### S-023 Switch view mode
As the user, I pick Details, List, or Icons from the View menu or Ctrl+Cmd+1/2/3.
Screens: details
Depends: S-002
Acceptance:
- [snap] Each mode has a snapshot.
- [self] The status bar has toggle icons for Details and Icons.
Status: todo

### S-024 Show extensions and hidden files
As the user, I turn on file extensions and hidden items from the View menu.
Depends: S-002
Acceptance:
- [self] Cmd+Shift+. toggles hidden items.
- [unit] Dotfiles hide by default.
Status: todo

### S-025 Pin folders to Quick access
As the user, I drag a folder to Quick access, or right-click to Pin, and unpin the same way.
Screens: tree
Depends: S-007
Acceptance:
- [unit] Pins save by bookmark so renamed folders still resolve.
- [self] Desktop, Downloads, Documents, Pictures are pinned at first.
Status: todo

### S-026 Open tabs
As the user, I press Cmd+T for a tab, Cmd+W to close, Ctrl+Tab to cycle, and Cmd+1-9 to jump.
Screens: tabs
Depends: S-003
Acceptance:
- [snap] Tabs sit in the title bar with a plus button and a close icon on hover.
- [unit] Closing the last tab closes the window.
- [self] Tabs restore on relaunch.
Status: todo

### S-027 Open a folder in a new tab
As the user, I middle-click or Cmd-click a folder to open it in a new tab.
Depends: S-026
Acceptance:
- [self] Both gestures work in the list, tree and breadcrumbs.
Status: todo

### S-028 Select like Explorer
As the user, I click, Cmd-click and Shift-click to select, drag a box on empty space, and use Cmd+A.
Depends: S-002
Acceptance:
- [self] Rubber band selection works in Details and Icons.
- [unit] Shift-click selects a range in sort order.
- [self] Selection count shows in the status bar.
Status: todo

## M4 Find and inspect

### S-030 Search from the top bar
As the user, I type in the search box (or press Cmd+F or F3) to find files in the current folder and below.
Screens: search
Depends: S-002
Acceptance:
- [self] Results stream in and the list shows a Location column.
- [unit] Search uses Spotlight for indexed folders. It falls back to a file scan for others.
- [self] Escape clears search and restores the folder.
Status: todo

### S-031 Show a preview pane
As the user, I toggle a preview pane that shows the selected file.
Screens: preview
Depends: S-002
Acceptance:
- [snap] The pane sits on the right with a drag edge. It shows images, PDFs, text, and a name, size, date summary for the rest.
- [self] Cmd+Shift+P toggles the pane. Option+letter shortcuts are not used.
Status: todo

### S-032 Quick Look with Space
As the user, I press Space on a file to preview it in Quick Look.
Depends: S-002
Acceptance:
- [self] Space opens and closes Quick Look. Arrow keys change the file.
Status: todo

### S-033 See Properties
As the user, I press Cmd+I to see size, dates, kind, location and permissions.
Screens: properties
Depends: S-002
Acceptance:
- [snap] The panel shows name, kind, size on disk, created, modified, and where.
- [unit] A folder's total size computes in the background with a spinner.
Status: todo

### S-034 Tag files
As the user, I add and remove Finder tags from the context menu or Properties.
Depends: S-033
Acceptance:
- [unit] Tags read and write through `tagNamesKey`.
- [self] A tag shows as a colored dot in the Tags column.
Status: todo

### S-035 See the status bar
As the user, I see the item count, the selection count and size.
Depends: S-002
Acceptance:
- [snap] "12 items", "3 items selected 4.1 MB".
Status: todo

## M5 System

### S-040 Guide Full Disk Access
As the user, I see a first-run screen that explains Full Disk Access and opens System Settings.
Screens: onboarding
Acceptance:
- [snap] The screen explains why in one sentence and has an Open Settings button.
- [self] After granting, Pane lists Desktop and Documents without prompts.
- [self] Without it, Pane still works with per-folder prompts.
Status: todo

### S-041 Use the command bar
As the user, I use icon buttons for New, Cut, Copy, Paste, Rename, Delete, Sort and View.
Screens: window
Depends: S-011, S-013, S-015
Acceptance:
- [snap] Buttons dim when they do not apply.
- [self] Each button matches its keyboard shortcut.
Status: todo

### S-042 Open from other apps in Pane
As the user, I turn on "Use Pane to open folders" and see Reveal in Finder from other apps open Pane.
Depends: S-003
Acceptance:
- [self] Revealing a file from Safari's downloads opens Pane with it selected.
- [self] Turning it off restores the earlier handler.
- [manual] The setting survives a reboot. [U] See the research file.
Status: todo

### S-043 Open Pane with a global shortcut
As the user, I press a global shortcut (default Control+Option+E) to open a new Pane window.
Depends: S-001
Acceptance:
- [self] The shortcut works with Pane in the background.
- [self] It can be changed in Settings.
Status: todo

### S-044 Browse network and iCloud
As the user, I see mounted SMB shares, iCloud Drive and external drives in the tree.
Screens: tree
Depends: S-007
Acceptance:
- [self] Drives and shares show under This Mac and Network.
- [self] iCloud placeholders show a cloud icon and download on open.
- [unit] Network folders refresh by polling every ten seconds.
Status: todo

### S-046 Connect to an SMB server
As the user, I choose Go > Connect to Server…, type `smb://nas/photos`, enter my name and password once, and the share appears in the tree.
Screens: connect
Depends: S-044
Acceptance:
- [snap] A sheet titled "Connect to Server" has an address field, a "Remember this password in my Keychain" checkbox, and "Connect" and "Cancel" buttons.
- [self] A bad address or a refused login shows the reason under the field and keeps the sheet open.
- [manual] Connecting mounts the share through `NetFS`, and the new share shows under Network and opens on Return.
- [unit] An address without `smb://` is rejected, and spaces and special characters in names are encoded.
- [self] Recent servers show in a list in the sheet, and the list can be cleared.
Status: todo

### S-047 Disconnect a share or eject a drive
As the user, I click the eject icon beside a share or drive in the tree to disconnect it.
Depends: S-046
Acceptance:
- [self] The eject icon shows only for ejectable volumes and shares.
- [self] A busy volume shows "Unable to eject. Items are in use." with a "Cancel" button.
- [self] A share that disappears leaves the tree and shows its folder as unavailable if it was open.
Status: todo

### S-048 Use cloud storage folders
As the user, I see iCloud Drive, Dropbox, Google Drive and OneDrive in the tree and browse them like any folder.
Screens: tree
Depends: S-044
Acceptance:
- [manual] Providers set up on this Mac show under "Cloud" in the Navigation pane. Test with at least iCloud Drive and one other provider. [U] These live under `~/Library/CloudStorage`.
- [snap] Items not yet on this Mac show a cloud icon and the Status bar says how many are online only.
- [self] Opening an online-only file downloads it, with progress, and then opens it.
- [self] The list updates when a provider finishes syncing.
- [unit] Placeholder files are listed by their real name and size, not `.icloud` names.
Status: todo

### S-045 Reveal and open in Terminal
As the user, I right-click a folder and choose Open in Terminal.
Depends: S-003
Acceptance:
- [self] Terminal opens at that folder.
Status: todo

## M6 Polish

### S-050 Use context menus
As the user, I right-click to see a short menu with icon row (Cut, Copy, Rename, Delete) and a "Show more" list.
Screens: context-menu
Depends: S-041
Acceptance:
- [snap] The menu has the icon row on top and Open, Open With, Properties, Tags, Services below.
- [self] Services from other apps appear.
Status: todo

### S-051 Show empty states
As the user, I see a clear message in an empty folder or an empty search.
Screens: empty-folder, search
Acceptance:
- [snap] Empty folder: "This folder is empty". Empty search: "No results for <text>".
Status: todo

### S-052 Change settings
As the user, I open Settings to change shortcuts, folders-first, extensions, the opening folder and the handler.
Screens: settings
Depends: S-021
Acceptance:
- [snap] Tabs: General, Shortcuts, Advanced.
- [self] Return opens or renames can be switched.
Status: todo

### S-053 Give Pane an icon
As the user, I see a Liquid Glass icon in the Dock and window.
Acceptance:
- [snap] The icon looks right in light, dark, and tinted looks.
Status: todo

### S-054 Make Pane keyboard friendly
As the user, I move focus between tree, list and address bar with F6.
Depends: S-007
Acceptance:
- [self] F6 and Shift+F6 cycle focus. VoiceOver reads names, kinds and sizes.
Status: todo

## Dropped
- Accounts, sharing, teams, sync servers, billing, analytics.
- Windows ads, recommendations, OneDrive upsell, Gallery, Network Neighborhood.
- A Recycle Bin: the Mac Trash stays.

## Later
- Dual pane and Drop Stack.
- FTP, SFTP and S3 (waiting on a user decision, see the brief).
- Zip browsing, batch rename.
- Tiles and Content views.
- Compare dialog inside the conflict sheet.
- Cloud features beyond folders the system provides: sharing links, selective sync, version history.
