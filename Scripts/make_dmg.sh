#!/usr/bin/env bash
# Build a DMG containing TrackMyMac.app and a symlink to /Applications.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")}"
APP="$ROOT/build/dist/TrackMyMac.app"
DIST_DIR="$ROOT/build/dist"
DMG="$DIST_DIR/TrackMyMac-${VERSION}.dmg"
DMG_LATEST="$DIST_DIR/TrackMyMac-latest.dmg"

if [ ! -d "$APP" ]; then
    echo "==> .app missing, building first…"
    bash "$ROOT/Scripts/build_app.sh"
fi

echo "==> Preparing DMG staging directory"
STAGE="$DIST_DIR/_dmg_stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG" "$DMG_LATEST"

echo "==> Creating DMG ($VERSION)"
hdiutil create \
    -volname "TrackMyMac ${VERSION}" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

cp "$DMG" "$DMG_LATEST"
rm -rf "$STAGE"

echo "==> DMG built:"
ls -lh "$DMG" "$DMG_LATEST"
echo "$DMG"
