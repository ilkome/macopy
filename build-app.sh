#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

EXE_NAME="MaCopy"
APP_DISPLAY="MaCopy by ilkome"
BUNDLE_ID="dev.ilkome.MaCopy"
APP_DIR="$APP_DISPLAY.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"

echo "→ swift build -c release"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp ".build/release/$EXE_NAME" "$MACOS_DIR/$EXE_NAME"

FRAMEWORKS_DIR="$CONTENTS/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
SPARKLE_SRC=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_SRC" ]; then
    rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
    cp -R "$SPARKLE_SRC" "$FRAMEWORKS_DIR/Sparkle.framework"
fi

install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$EXE_NAME" 2>/dev/null || true

VERSION="${APP_VERSION:-1.0}"
BUILD="${APP_BUILD:-1}"
FEED_URL="${SU_FEED_URL:-https://raw.githubusercontent.com/ilkome/macopy/main/appcast.xml}"
PUBLIC_KEY="${SU_PUBLIC_ED_KEY:-ACtaihbc3SKKgsYkJ9QLAbZWA8ENfBiyjGaZUwP+Fac=}"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_DISPLAY</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_DISPLAY</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$EXE_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>SUFeedURL</key>
    <string>$FEED_URL</string>
    <key>SUPublicEDKey</key>
    <string>$PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUEnableInstallerLauncherService</key>
    <true/>
</dict>
</plist>
PLIST

SIGN_IDENTITY="MaCopy Dev"
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    echo "⚠  '$SIGN_IDENTITY' not found. Run ./setup-signing.sh once for persistent Accessibility permission. Falling back to ad-hoc."
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "→ готово: $(pwd)/$APP_DIR"
