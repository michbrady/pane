#!/bin/zsh
# Runs the in-app self-test on a throwaway home folder. Exit code 0 when every check passed.
set -u
here=${0:A:h}
rm -rf ~/Library/Saved\ Application\ State/com.michaelbrady.pane.savedState
defaults delete com.michaelbrady.pane.test 2>/dev/null
$here/make-fixture.sh /tmp/Pane-self-home
APP_HOME=/tmp/Pane-self-home ~/Applications/Pane.app/Contents/MacOS/Pane --selftest
