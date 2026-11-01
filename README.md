# Pane

A file manager for the Mac that works the way Windows File Explorer does, for people who are switching from Windows.
A BradysBit app. Native SwiftUI, macOS 26 or later, free.

> **Status: in development.** Browsing and basic file operations work. Tabs, search, preview, and remote servers are not built yet.

## What works today

- Windows 11 Explorer layout: a folder tree, an Address bar with breadcrumbs, and a Details view with Name, Date modified, Type, and Size columns.
- Go back, forward, and up. Type a path in the Address bar (`~`, `~/Documents`).
- Cut, Copy, and Paste, where Cut really moves the files (Finder has no Cut).
- A conflict sheet (Replace, Skip, Keep Both), the Trash with Undo, and Delete Immediately with a confirmation.
- Rename with F2 and New Folder with Shift-Command-N.

## What is planned

Tabs, search, a preview pane, tags, SMB and cloud storage folders, and FTP, SFTP, and S3 servers. The full backlog is in
[`docs/STORIES.md`](docs/STORIES.md), and the plan is in [`docs/BRIEF.md`](docs/BRIEF.md).

## Build it

You need macOS 26 or later and Swift 6.2 or later. There is no Xcode project.

```sh
./build.sh --open            # builds and installs /Applications/Pane.app, then opens it
swift test --scratch-path ~/Library/Developer/Pane/test-build
tools/selftest.sh            # the app's own checks on a throwaway folder
```

`tools/snap.sh` writes light and dark screenshots of every view to `/tmp/Pane-shots`. Tests and snapshots use a throwaway
home folder (`APP_HOME`), so they never touch your files or settings.

`./release.sh` signs the app with a Developer ID certificate and has Apple notarize it. It needs your own certificate and
notary login. [`CLAUDE.md`](CLAUDE.md) and [`ARCHITECTURE.md`](ARCHITECTURE.md) describe how the code fits together.

## Privacy

Pane reads the folders you open and nothing else. It sends no data anywhere and has no analytics.

## License

[MIT](LICENSE)
