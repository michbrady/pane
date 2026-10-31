#!/bin/zsh
# Snapshots of every page in light and dark, on a throwaway home folder.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=window,settings tools/snap.sh
set -u
here=${0:A:h}
app=~/Applications/Pane.app/Contents/MacOS/Pane
home=/tmp/Pane-home
shots=/tmp/Pane-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.michaelbrady.pane.savedState
defaults delete com.michaelbrady.pane.test 2>/dev/null
$here/make-fixture.sh $home
rm -rf $shots
APP_HOME=$home APP_SNAPSHOT=$shots $app
