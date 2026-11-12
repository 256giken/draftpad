#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draftpad.app
VERSION=${VERSION:-0.0.0}
SIGN_IDENTITY=${SIGN_IDENTITY:--}
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"
swiftc -O -target arm64-apple-macos13.0 Sources/*.swift -o "$APP/Contents/MacOS/Draftpad"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Draftpad</string>
  <key>CFBundleIdentifier</key><string>jp.co.0x100.draftpad</string>
  <key>CFBundleName</key><string>Draftpad</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
cp web/* "$APP/Contents/Resources/web/"
cp -R node_modules/monaco-editor/min/vs "$APP/Contents/Resources/web/vs"
TIMESTAMP=--timestamp
[ "$SIGN_IDENTITY" = "-" ] && TIMESTAMP=--timestamp=none
codesign --force --options runtime "$TIMESTAMP" --sign "$SIGN_IDENTITY" "$APP"
