#!/bin/zsh
# Proves box selection with a real mouse drag: from empty space below the rows, up across the last four rows.
# It moves your cursor for about five seconds, so run it when you are not using the Mac. It launches Pane on a
# throwaway folder and brings it to the front; drag.swift refuses to click unless Pane is the frontmost window.
# Writes /tmp/Pane-box-after.png, a picture of the screen after the drag: the last four rows should be selected.
# Needs Accessibility permission for your terminal. Coordinates assume the default 1100 x 720 window.
set -u
here=${0:A:h}
home=/tmp/Pane-drag-home
pkill -x Pane 2>/dev/null; sleep 1
$here/make-fixture.sh $home
rm -rf ~/Library/Saved\ Application\ State/com.michaelbrady.pane.savedState
defaults delete com.michaelbrady.pane.test 2>/dev/null
# `tools/box-test.sh icons` drags in the Icons view, from below the icons up across the second row.
[[ ${1:-} == icons ]] && defaults write com.michaelbrady.pane.test view.mode icons
(APP_HOME=$home APP_START=$home/Documents /Applications/Pane.app/Contents/MacOS/Pane >/dev/null 2>&1 &)
sleep 4
osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "Pane") to true' 2>/dev/null
sleep 1
if [[ ${1:-} == icons ]]; then from=(700 600); to=(250 300); else from=(700 600); to=(700 330); fi
swift $here/drag.swift $from $to || { pkill -x Pane; exit 1; }
sleep 1
screencapture -x /tmp/Pane-box-after.png
pkill -x Pane
echo "wrote /tmp/Pane-box-after.png"
