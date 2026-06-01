#!/usr/bin/env bash
set -euo pipefail

# Build & package TrackMyMac.app
# Requires: Xcode Command Line Tools (no full Xcode required).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
APP_NAME="TrackMyMac"
BUNDLE_ID="com.trackmymac.app"
DIST_DIR="$ROOT/build/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "==> Cleaning previous build"
rm -rf "$DIST_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "==> Building Swift package (release)"
swift build -c "$CONFIG" --arch arm64 --arch x86_64 2>/dev/null || \
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
echo "==> Bin path: $BIN_PATH"

echo "==> Assembling .app bundle"
cp "$BIN_PATH/${APP_NAME}" "$MACOS_DIR/${APP_NAME}"
chmod +x "$MACOS_DIR/${APP_NAME}"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

# Generate a tiny PkgInfo
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Create a simple icon if /usr/bin/sips is available; otherwise skip.
if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
    ICONSET="$DIST_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET"
    # Generate a placeholder square PNG using Python if available
    PY="/Users/liuxinyutencent/.workbuddy/binaries/python/versions/3.13.12/bin/python3"
    if [ ! -x "$PY" ]; then PY="$(command -v python3 || true)"; fi
    if [ -n "$PY" ]; then
        "$PY" "$ROOT/Scripts/make_icon.py" "$DIST_DIR/icon_1024.png" || true
        if [ -f "$DIST_DIR/icon_1024.png" ]; then
            for size in 16 32 64 128 256 512 1024; do
                sips -z "$size" "$size" "$DIST_DIR/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
                if [ "$size" -lt 1024 ]; then
                    dbl=$((size*2))
                    sips -z "$dbl" "$dbl" "$DIST_DIR/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
                fi
            done
            iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"
        fi
    fi
fi

echo "==> Code signing (ad-hoc)"
codesign --force --deep --sign - \
    --entitlements "$ROOT/Resources/TrackMyMac.entitlements" \
    --options runtime \
    "$APP_DIR" 2>/dev/null || \
codesign --force --deep --sign - \
    --entitlements "$ROOT/Resources/TrackMyMac.entitlements" \
    "$APP_DIR"

echo
echo "==> Built: $APP_DIR"
echo "==> First run: open '$APP_DIR'"
echo "    macOS will prompt to grant Accessibility / Input Monitoring / Screen Recording."
