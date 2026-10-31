#!/bin/zsh
# Builds Pane, signs it with your Developer ID, sends it to Apple to notarize,
# staples the ticket, and writes a zip you can share.
# Output: ~/Library/Developer/Pane/release/Pane.zip
#
# One time first: store your notary login in the keychain.
#   xcrun notarytool store-credentials "pane-notary" --apple-id <your Apple ID> --team-id <TEAMID>
# It asks for an app-specific password (appleid.apple.com > Sign-In and Security).
#
# Usage: ./release.sh
#        NOTARY_PROFILE=other-name ./release.sh
set -euo pipefail
here=${0:A:h}
name="Pane"
profile="${NOTARY_PROFILE:-pane-notary}"
out="$HOME/Library/Developer/$name/release"

identity=$(security find-identity -v -p codesigning | grep -m1 -o '"Developer ID Application: [^"]*"' | tr -d '"' || true)
[[ -n "$identity" ]] || { echo "No Developer ID Application certificate in the keychain."; exit 1; }
xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1 || {
  echo "No notary login named \"$profile\". Run:"
  echo "  xcrun notarytool store-credentials \"$profile\" --apple-id <your Apple ID> --team-id <TEAMID>"
  exit 1
}

"$here/build.sh" >/dev/null
app="$HOME/Applications/$name.app"
# Hardened runtime and a secure timestamp are what notarization requires.
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --strict --deep --verbose=2 "$app"

mkdir -p "$out"
upload="$out/$name-upload.zip"
rm -f "$upload"
ditto -c -k --keepParent "$app" "$upload"
xcrun notarytool submit "$upload" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
spctl --assess --type execute --verbose=2 "$app"

rm -f "$upload" "$out/$name.zip"
ditto -c -k --keepParent "$app" "$out/$name.zip"
echo "ready: $out/$name.zip (signed: $identity)"
