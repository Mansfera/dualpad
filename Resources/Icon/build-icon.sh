#!/bin/bash
# Compiles DualPad.icon (Icon Composer) into Resources/Assets.car (macOS 26 glass icon) and
# Resources/AppIcon.icns (older macOS), plus a 1024 preview PNG. The output is kept with the
# sources, so build.sh needs neither this script nor Xcode's icon tools. Requires Xcode 26+.
set -euo pipefail
cd "$(dirname "$0")"
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp -R DualPad.icon "$TMP/AppIcon.icon"
mkdir "$TMP/out"
xcrun actool "$TMP/AppIcon.icon" --compile "$TMP/out" --app-icon AppIcon --platform macosx \
    --minimum-deployment-target 14.0 --target-device mac \
    --output-partial-info-plist "$TMP/out/partial.plist" >/dev/null
cp "$TMP/out/Assets.car" "$TMP/out/AppIcon.icns" ..

if [ -x "$ICTOOL" ]; then
    "$ICTOOL" DualPad.icon --export-image --output-file preview.png --platform macOS --rendition Default \
        --width 1024 --height 1024 --scale 1 >/dev/null
fi
echo "Icon rebuilt"
