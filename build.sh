#!/bin/bash
# Builds DualPad.app into build/. `./build.sh install` also copies it to /Applications and starts it.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/DualPad.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc Sources/*.swift \
  -o "$APP/Contents/MacOS/DualPad" \
  -framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement \
  -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 -O

cp Info.plist "$APP/Contents/Info.plist"
# Testing the update banner by hand: SIMULATE_VERSION=0.9.0 ./build.sh builds an app that thinks it's old.
if [ -n "${SIMULATE_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SIMULATE_VERSION" "$APP/Contents/Info.plist"
  echo "Simulating version $SIMULATE_VERSION"
fi
cp -R Resources/Fonts Resources/Assets.car Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - --identifier com.mansfera.dualpad "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x DualPad || true
  sleep 0.5
  rm -rf /Applications/DualPad.app
  cp -R "$APP" /Applications/
  open /Applications/DualPad.app
  echo "Installed /Applications/DualPad.app"
fi
