#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "usage: ./release.sh <version>"
    echo "  example: ./release.sh 1.0.1"
    exit 1
fi

REPO="ilkome/macopy"
APP_DISPLAY="MaCopy by ilkome"
APP_DIR="$APP_DISPLAY.app"
BUILD_DIR="release-artifacts/$VERSION"
ZIP_NAME="MaCopy-$VERSION.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
if [ ! -x "$SIGN_UPDATE" ]; then
    SIGN_UPDATE="$(ls /opt/homebrew/Caskroom/sparkle/*/bin/sign_update 2>/dev/null | head -1)"
fi
if [ ! -x "$SIGN_UPDATE" ]; then
    echo "⚠  sign_update not found. Run: swift package resolve"
    exit 1
fi

echo "→ build version $VERSION"
APP_VERSION="$VERSION" APP_BUILD="$(date +%s)" ./build-app.sh

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "→ zip $ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
SIZE=$(stat -f %z "$ZIP_PATH")

echo "→ sign update"
SIG_LINE=$("$SIGN_UPDATE" "$ZIP_PATH" | head -1)
ED_SIG=$(echo "$SIG_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')

if [ -z "$ED_SIG" ]; then
    echo "⚠  failed to extract signature from: $SIG_LINE"
    exit 1
fi

PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
APPCAST_ITEM=$(cat <<ITEM
        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <enclosure
                url="https://github.com/$REPO/releases/download/v$VERSION/$ZIP_NAME"
                length="$SIZE"
                type="application/octet-stream"
                sparkle:edSignature="$ED_SIG" />
        </item>
ITEM
)

echo "→ appcast item (paste into appcast.xml inside <channel>):"
echo ""
echo "$APPCAST_ITEM"
echo ""
echo "→ then:"
echo "    gh release create v$VERSION \"$ZIP_PATH\" --title \"v$VERSION\" --notes \"...\""
echo "    git add appcast.xml && git commit -m 'release $VERSION' && git push"
