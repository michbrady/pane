#!/bin/zsh
# Proves drag and drop with real mouse events: a file dragged onto a folder in the Navigation pane
# moves it, and Option-drag copies it. It moves your cursor for about ten seconds, so run it when
# you are not using the Mac. It launches Pane on a throwaway folder, brings it to the front, and
# drag.swift refuses to click unless Pane is the frontmost window.
# Needs Accessibility permission for your terminal. Coordinates assume the default 1100 x 720 window.
set -u
here=${0:A:h}
home=/tmp/Pane-drag-home
pkill -x Pane 2>/dev/null; sleep 1
$here/make-fixture.sh $home
rm -rf ~/Library/Saved\ Application\ State/com.michaelbrady.pane.savedState
defaults delete com.michaelbrady.pane.test 2>/dev/null
(APP_HOME=$home APP_START=$home/Documents ~/Applications/Pane.app/Contents/MacOS/Pane >/dev/null 2>&1 &)
sleep 4
osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "Pane") to true' 2>/dev/null
sleep 1
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi }

# Notes.txt row -> "Downloads" in the This Mac tree: same volume, so it moves.
swift $here/drag.swift 308 302 100 343 || { pkill -x Pane; exit 1; }
sleep 2
check "dropping on a tree folder moves the file" '[[ -f $home/Downloads/Notes.txt && ! -e $home/Documents/Notes.txt ]]'

# file2.txt row -> "Pictures" in the tree, holding Option: copies.
swift $here/drag.swift 308 254 91 439 option || { pkill -x Pane; exit 1; }
sleep 2
check "Option-drop copies the file" '[[ -f $home/Pictures/file2.txt && -f $home/Documents/file2.txt ]]'

pkill -x Pane
[[ $fail == 0 ]] && echo "DRAG TEST PASS" || echo "DRAG TEST FAIL"
exit $fail
