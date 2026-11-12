#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draftpad.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"
swiftc -O -target arm64-apple-macos13.0 Sources/*.swift -o "$APP/Contents/MacOS/Draftpad"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Draftpad</string>
  <key>CFBundleIdentifier</key><string>local.draftpad</string>
  <key>CFBundleName</key><string>Draftpad</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
cp web/* "$APP/Contents/Resources/web/"
cp -R node_modules/monaco-editor/min/vs "$APP/Contents/Resources/web/vs"
codesign --force --deep -s - "$APP"
