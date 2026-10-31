# Pane design plan

Written with the mac-design skill. The brief stays on one page, so the plan lives here.

## Archetype
Sidebar window, macOS 26 or later, with native Liquid Glass chrome and the Mac's own accent color. Windows 11 Explorer supplies the layout, not the look. No menu bar item in version one. The global shortcut (S-043) is the only quick entry point.

## Feeling
Quick and familiar. A Windows user's hands know where things are. Every action answers in the same frame and offers Undo.

## Layout
`NavigationSplitView` with `.inspector`.

| Explorer part | Pane part | Surface |
| --- | --- | --- |
| Tab strip | Standard macOS window tabs (`NSWindow` tabbing) in the title bar, plus button | system |
| Navigation pane | Sidebar column: Quick access, This Mac, Network. Glass comes from the system | `NavigationSplitView` sidebar, `List` + `OutlineGroup` replaced by `NSOutlineView` for large folders |
| Command bar | The window toolbar over the content column | `.toolbar` |
| Address bar and Search box | A slim row under the toolbar: Go back, Go forward, Go up, breadcrumbs, and `.searchable` at the trailing edge | custom row (see Custom chrome) |
| Details view | `NSTableView` in `NSViewRepresentable` for Details and List, a grid for Icons | content column |
| Preview pane | `.inspector` on the split view | `.inspector` |
| Status bar | A 22 pt bar at the bottom of the content column, `.secondary` text, no glass | `safeAreaInset(.bottom)` |

Custom chrome: the Address bar is a custom row because breadcrumbs, an editable path, and sibling menus need the full width and the system toolbar cannot hold them. It uses system fonts, 4 pt spacing, and a plain `.bar` material, not glass on glass.

## Toolbar (Command bar)
Three groups, split by `ToolbarSpacer(.fixed)`, all over the content column:
1. Create and edit: New (menu: Folder, File), Cut, Copy, Paste, Rename, Move to Trash.
2. Arrange: Sort (menu), View (menu: Details, List, Icons).
3. Trailing: Search box (`.searchable`), Preview pane toggle (`sidebar.trailing`).
Monochrome SF Symbols, each with a title and `.help` that starts with a verb and names its shortcut. No prominent action. Every item also lives in the menu bar. Items dim when they do not apply.

## Command map
| Action | Menu | Shortcut |
| --- | --- | --- |
| New Window | File | Cmd+N |
| New Tab | File | Cmd+T |
| New Folder | File | Cmd+Shift+N |
| Open | File | Return, Cmd+Down |
| Close Tab | File | Cmd+W |
| Properties | File | Cmd+I |
| Rename | File | F2 |
| Move to Trash | File | Delete, Cmd+Delete |
| Delete Immediately… | File | Shift+Delete |
| Undo / Redo (named) | Edit | Cmd+Z, Cmd+Shift+Z |
| Cut / Copy / Paste | Edit | Cmd+X, Cmd+C, Cmd+V |
| Select All | Edit | Cmd+A |
| Find | Edit | Cmd+F, F3 |
| Show Navigation Pane | View | Ctrl+Cmd+S (system `SidebarCommands`) |
| Show Preview Pane | View | Cmd+Shift+P |
| Show Hidden Items | View | Cmd+Shift+. |
| Show File Extensions | View | none |
| As Details / As List / As Icons | View | Ctrl+Cmd+1, 2, 3 |
| Sort By | View | submenu |
| Refresh | View | Cmd+R, F5 |
| Go Back / Forward / Enclosing Folder | Go | Cmd+[, Cmd+], Cmd+Up |
| Go to Address… | Go | Cmd+L, F4 |
| Go to Tab 1 to 9 | Window | Cmd+1 to Cmd+9 |
| Next / Previous Tab | Window | Ctrl+Tab, Ctrl+Shift+Tab |
| Settings… | Pane | Cmd+Comma |
| Quick Look | File | Space |
| Move focus | View | F6, Shift+F6 |

Menu order: Pane, File, Edit, View, Go, Window, Help. Cmd+Shift+3, 4, 5 and F11 stay unbound. Function keys need the Mac's "Use F1, F2 etc. as standard function keys" setting or the fn key. Settings states this once, and every F-key command has a Cmd or Return equivalent.

## Empty states
| Page | Shows |
| --- | --- |
| Empty folder | `ContentUnavailableView` "This folder is empty" |
| Empty search | "No results for <text>" |
| Folder Pane cannot read | "Unable to read this folder" with "Open Settings" |
| No Quick access pins | Defaults pinned: Desktop, Downloads, Documents, Pictures |

## Rules this plan sets
- No focus ring or selected text when a window opens (`.noInitialFocus()`). The Navigation pane list may hold focus.
- Cut items show at 50% opacity.
- Folder icons come from `NSWorkspace.icon(forFile:)`, cached by extension.
- Dates read like "10/31/2026 2:14 PM", sizes like "4 KB", per the user's region formats.
- Every surface gets a light and a dark snapshot as the key window.
