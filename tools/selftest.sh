#!/bin/zsh
# Runs the in-app self-test on a throwaway home folder. Exit code 0 when every check passed.
set -u
here=${0:A:h}
# An earlier run still shutting down would share the throwaway folder and settings. Wait for it to exit.
if pgrep -x Pane >/dev/null; then pkill -x Pane; for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Pane >/dev/null || break; sleep 0.5; done; fi
rm -rf ~/Library/Saved\ Application\ State/com.michaelbrady.pane.savedState
defaults delete com.michaelbrady.pane.test 2>/dev/null
$here/make-fixture.sh /tmp/Pane-self-home
APP_HOME=/tmp/Pane-self-home /Applications/Pane.app/Contents/MacOS/Pane --selftest
