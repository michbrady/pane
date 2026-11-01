# Pane web page

Upload these three files to the same folder on the web server (`bradysbit.com/pane/`):

- `index.html` is the whole page. The screenshots, logo, and styles are inside it.
- `privacy.html` is the privacy and terms page. It must sit next to `index.html`.
- `Pane.dmg` is the download: an installer disk image with Pane and an Applications folder to drag it onto.
  The page links to it as `Pane.dmg`, so it must sit next to `index.html`.

`Pane.dmg` is not kept in git. To make a new one and update the page (the size and checksum are filled in for you):

```sh
./build.sh                       # build the app into ~/Applications
tools/make-dmg.sh                # pack it into website/Pane.dmg (lets Finder lay out the window)
python3 website/source/build.py  # rewrites website/index.html and website/privacy.html
```

For a notarized download, run `./release.sh` (signs and notarizes the app), make the DMG from that app, then
notarize and staple the DMG itself (`xcrun stapler staple website/Pane.dmg`). `build.py` says "notarized" on the page
only when `xcrun stapler validate` passes on the DMG.

The page's text is in `website/source/page.html` and `privacy.html`; screenshots are in `website/source/shots/`
(made with `tools/snap.sh`). The picture on the installer window is drawn by `tools/dmg-background.swift`.
