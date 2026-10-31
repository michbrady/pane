# Pane

A Finder companion for the Mac with a Windows 11 File Explorer layout, for people switching from Windows.

## Replaces
Finder, and the Windows Explorer habits Finder breaks (cut to move, Return to open, an editable address bar, a folder tree).

## Main jobs
1. Browse folders: tree pane, address bar with breadcrumbs, Details view with sortable columns, tabs.
2. Move and copy files the Windows way: Cut, Copy, Paste, drag with modifiers, a conflict dialog, undo.
3. Find and inspect: search box in the top bar, preview pane and Quick Look, Properties panel, tags.

## Data
- No database. Pane reads the file system.
- Settings: view mode, sort, columns per folder, pinned Quick access folders, open tabs, shortcut choices.

## Shape
Sidebar window (tree on the left, content on the right, optional preview pane, status bar), macOS 26 or later. Local data. Works offline. No accounts. Not sandboxed, notarized, outside the Mac App Store, with Full Disk Access granted by the user.

## System hooks
- Optional default for opening folders and "Reveal in Finder" from other apps (`NSFileViewer`, `public.folder`). Finder keeps the Desktop, Trash UI, AirDrop and Put Back.
- Global shortcut to open a Pane window (like Win+E).
- Quick Look, tags, Spotlight search.
- Network and cloud: connect to SMB servers, browse mounted shares, and use iCloud Drive, Dropbox, Google Drive and OneDrive folders the system provides.

## Reference
None. Windows 11 File Explorer cannot be opened on this Mac. Layout and shortcuts come from `docs/research/explorer-style-file-manager.md`.

## Look
Native Mac chrome (system sidebar, toolbar, Liquid Glass, system fonts) arranged like Windows 11 Explorer, with the Mac's own accent color. Chosen by the user.

## Keys
- Ctrl maps to Cmd. F2 renames, Return opens, F3 searches, F4 or Cmd+L focuses the address bar, F5 refreshes.
- Delete and Cmd+Delete both send to the Trash (chosen by the user). Backspace does not go Back.
- No Option+letter shortcuts. Open: Cmd+1-9 vs Finder view modes, Cmd+Shift+3-5 screenshots, F11 Show Desktop, to settle in `user-stories`.

## Not in version one
- Dual pane and Drop Stack.
- Windows 11 Tiles and Content views (Details, List and Icons only).
- Zip browsing and batch rename (system extract still works).
- Undecided, waiting on the user: FTP, SFTP and S3. They need Pane's own client, because macOS no longer mounts FTP.
