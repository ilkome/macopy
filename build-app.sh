#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ListTestSwiftUI"
BUNDLE_ID="com.ilkome.ListTestSwiftUI"
APP_DIR="$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"

echo "→ swift build -c release"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp ".build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

echo "→ готово: $(pwd)/$APP_DIR"
