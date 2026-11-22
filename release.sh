#!/bin/bash
# Builds a release, publishes it on GitHub and updates the Homebrew cask in Mansfera/homebrew-tap.
# usage: ./release.sh <version>, e.g. ./release.sh 1.0.1
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: ./release.sh <version>, e.g. ./release.sh 1.0.1"; exit 1; }
V="$1"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "The version must look like 1.2.3"; exit 1; }
cd "$(dirname "$0")"
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first: the release is built from HEAD."; exit 1; }
! git rev-parse -q --verify "refs/tags/v$V" >/dev/null || { echo "v$V is already tagged."; exit 1; }

Tests/update-policy.sh >/dev/null || { echo "Tests/update-policy.sh failed: not releasing."; exit 1; }

# The build number counts from the last commit, so a failed run that's tried again doesn't bump it twice.
mkdir -p build
git show HEAD:Info.plist > build/Info.head.plist
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" build/Info.head.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Info.plist
env -u SIMULATE_VERSION ./build.sh

rm -rf build/dmg dist && mkdir -p build/dmg dist
ditto build/DualPad.app build/dmg/DualPad.app
ln -s /Applications build/dmg/Applications
DMG="dist/DualPad-$V.dmg"
hdiutil create -volname "DualPad" -srcfolder build/dmg -ov -format UDZO "$DMG" >/dev/null
rm -rf build/dmg  # the staging copy of the app is only needed inside the DMG
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
echo "DMG $DMG  sha256 $SHA"

git add Info.plist
git diff --cached --quiet || git commit -q -m "Release $V"
git tag "v$V"
git push -q origin HEAD "v$V"
gh release create "v$V" "$DMG" -R Mansfera/dualpad --verify-tag --title "DualPad $V" \
  --notes "Install: \`brew install --cask mansfera/tap/dualpad\`, or open the DMG and drag DualPad to Applications."

TAP=build/tap
rm -rf "$TAP"
gh repo clone Mansfera/homebrew-tap "$TAP" -- -q
sed -e "s/__VERSION__/$V/" -e "s/__SHA256__/$SHA/" Homebrew/dualpad.rb > "$TAP/Casks/dualpad.rb"
git -C "$TAP" add Casks/dualpad.rb
git -C "$TAP" commit -q -m "dualpad $V"
git -C "$TAP" push -q
rm -rf "$TAP"
echo "Released $V: brew install --cask mansfera/tap/dualpad"
