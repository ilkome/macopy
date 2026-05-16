#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

EXE_NAME="MaCopy"
APP_DISPLAY="MaCopy by ilkome"
BUNDLE_ID="dev.ilkome.MaCopy"
APP_DIR="$APP_DISPLAY.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"

if [ -z "${SU_PUBLIC_ED_KEY:-}" ]; then
    echo "✗ SU_PUBLIC_ED_KEY is not set." >&2
    echo "  Sparkle requires the public half of your EdDSA key pair to verify updates." >&2
    echo "  Building without it would ship an app that can only be updated by whoever holds the default" >&2
    echo "  private key - i.e. no one. See README.md -> 'Releases and auto-update (Sparkle)'." >&2
    echo "  Run: export SU_PUBLIC_ED_KEY='<your public key>' (consider adding it to ~/.zshrc)." >&2
    exit 1
fi

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

SQLCIPHER_SRC=".build/artifacts/sqlcipher.swift/SQLCipher/SQLCipher.xcframework/macos-arm64_x86_64/SQLCipher.framework"
if [ -d "$SQLCIPHER_SRC" ]; then
    rm -rf "$FRAMEWORKS_DIR/SQLCipher.framework"
    cp -R "$SQLCIPHER_SRC" "$FRAMEWORKS_DIR/SQLCipher.framework"
else
    echo "✗ SQLCipher.framework not found at $SQLCIPHER_SRC" >&2
    exit 1
fi

install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$EXE_NAME" 2>/dev/null || true

VERSION="${APP_VERSION:-1.0}"
BUILD="${APP_BUILD:-1}"
FEED_URL="${SU_FEED_URL:-https://raw.githubusercontent.com/ilkome/macopy/main/appcast.xml}"
PUBLIC_KEY="$SU_PUBLIC_ED_KEY"

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
ENTITLEMENTS="MaCopy.entitlements"

if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    SIGN_ARG="$SIGN_IDENTITY"
else
    echo "⚠  '$SIGN_IDENTITY' not found. Run ./setup-signing.sh once for persistent Accessibility permission. Falling back to ad-hoc."
    SIGN_ARG="-"
fi

SPARKLE_FW="$FRAMEWORKS_DIR/Sparkle.framework"
SPARKLE_VB="$SPARKLE_FW/Versions/B"

sign() {
    codesign --force --options=runtime --timestamp=none --sign "$SIGN_ARG" "$1"
}

if [ -d "$SPARKLE_FW" ]; then
    sign "$SPARKLE_VB/XPCServices/Downloader.xpc"
    sign "$SPARKLE_VB/XPCServices/Installer.xpc"
    sign "$SPARKLE_VB/Updater.app"
    sign "$SPARKLE_VB/Autoupdate"
    sign "$SPARKLE_VB"
    sign "$SPARKLE_FW"
fi

SQLCIPHER_FW="$FRAMEWORKS_DIR/SQLCipher.framework"
if [ -d "$SQLCIPHER_FW" ]; then
    sign "$SQLCIPHER_FW/Versions/A"
    sign "$SQLCIPHER_FW"
fi

codesign --force --options=runtime --timestamp=none \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_ARG" "$APP_DIR"

echo "→ verify"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

APP_FLAGS=$(codesign -dvvv "$APP_DIR" 2>&1 | grep '^CodeDirectory' || true)
echo "$APP_FLAGS"
if ! echo "$APP_FLAGS" | grep -q 'runtime'; then
    echo "✗ hardened runtime flag missing on $APP_DIR" >&2
    exit 1
fi

if ! codesign -d --entitlements - "$APP_DIR" 2>&1 | grep -q 'disable-library-validation'; then
    echo "✗ disable-library-validation entitlement missing on $APP_DIR" >&2
    exit 1
fi

XPC_FLAGS=$(codesign -dvvv "$SPARKLE_VB/XPCServices/Installer.xpc" 2>&1 | grep '^CodeDirectory' || true)
if ! echo "$XPC_FLAGS" | grep -q 'runtime'; then
    echo "✗ hardened runtime flag missing on Installer.xpc" >&2
    exit 1
fi

SQLCIPHER_FLAGS=$(codesign -dvvv "$SQLCIPHER_FW" 2>&1 | grep '^CodeDirectory' || true)
if ! echo "$SQLCIPHER_FLAGS" | grep -q 'runtime'; then
    echo "✗ hardened runtime flag missing on SQLCipher.framework" >&2
    exit 1
fi

echo "→ готово: $(pwd)/$APP_DIR"
