#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draftpad.app
VERSION=${VERSION:-0.0.0}
SIGN_IDENTITY=${SIGN_IDENTITY:--}
SPARKLE_VERSION=2.6.4
SPARKLE_SHA256=50612a06038abc931f16011d7903b8326a362c1074dabccb718404ce8e585f0b
SPARKLE_DIR=vendor/Sparkle-$SPARKLE_VERSION
SPARKLE_TAR=vendor/Sparkle-$SPARKLE_VERSION.tar.xz
mkdir -p vendor
[ -f "$SPARKLE_TAR" ] || { curl -fsSL -o "$SPARKLE_TAR.part" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" && mv "$SPARKLE_TAR.part" "$SPARKLE_TAR"; }
echo "$SPARKLE_SHA256  $SPARKLE_TAR" | shasum -a 256 -c -
if [ ! -d "$SPARKLE_DIR" ]; then
  rm -rf "$SPARKLE_DIR.tmp"
  mkdir "$SPARKLE_DIR.tmp"
  tar -xJf "$SPARKLE_TAR" -C "$SPARKLE_DIR.tmp"
  mv "$SPARKLE_DIR.tmp" "$SPARKLE_DIR"
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources/web" "$APP/Contents/Resources/licenses"
swiftc -O -target arm64-apple-macos13.0 -F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  Sources/*.swift -o "$APP/Contents/MacOS/Draftpad"
ditto "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Draftpad</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>jp.co.0x100.draftpad</string>
  <key>CFBundleName</key><string>Draftpad</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>SUFeedURL</key><string>https://github.com/256giken/draftpad/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>IlO9mc+5vo2ucVAAJgvWaRZs9T3sToZdhPmBmb8mGdU=</string>
</dict>
</plist>
PLIST
cp assets/AppIcon.icns "$APP/Contents/Resources/"
cp web/* "$APP/Contents/Resources/web/"
cp -R node_modules/monaco-editor/min/vs "$APP/Contents/Resources/web/vs"
LICENSES="$APP/Contents/Resources/licenses"
cp node_modules/monaco-editor/LICENSE "$LICENSES/monaco-editor-LICENSE"
[ -f node_modules/monaco-editor/ThirdPartyNotices.txt ] && cp node_modules/monaco-editor/ThirdPartyNotices.txt "$LICENSES/monaco-editor-ThirdPartyNotices.txt"
cp "$SPARKLE_DIR/LICENSE" "$LICENSES/sparkle-LICENSE"
TIMESTAMP=--timestamp
APP_ENTITLEMENTS=()
if [ "$SIGN_IDENTITY" = "-" ]; then
  TIMESTAMP=--timestamp=none
  # ad-hoc signatures have no Team ID, so library validation would reject Sparkle.framework
  cat > build/ad-hoc.entitlements <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
</plist>
PLIST
  APP_ENTITLEMENTS=(--entitlements build/ad-hoc.entitlements)
fi
SPARKLE_B="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for target in "$SPARKLE_B/Autoupdate" "$SPARKLE_B/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
  codesign --force --options runtime "$TIMESTAMP" --sign "$SIGN_IDENTITY" "$target"
done
codesign --force --options runtime "$TIMESTAMP" ${APP_ENTITLEMENTS[@]+"${APP_ENTITLEMENTS[@]}"} --sign "$SIGN_IDENTITY" "$APP"
