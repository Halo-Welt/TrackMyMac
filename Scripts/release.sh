#!/usr/bin/env bash
# Build, package, and publish a GitHub Release.
# Usage: bash Scripts/release.sh [version]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")}"
TAG="v${VERSION}"

echo "==> Releasing $TAG"

bash "$ROOT/Scripts/build_app.sh"
bash "$ROOT/Scripts/make_dmg.sh" "$VERSION"

DMG="$ROOT/build/dist/TrackMyMac-${VERSION}.dmg"
DMG_LATEST="$ROOT/build/dist/TrackMyMac-latest.dmg"

NOTES_FILE="$(mktemp)"
cat > "$NOTES_FILE" <<EOF
## TrackMyMac ${VERSION}

下载下方 \`TrackMyMac-${VERSION}.dmg\`（或 \`TrackMyMac-latest.dmg\`），双击挂载后把 TrackMyMac 拖到 Applications。

首次启动会被 Gatekeeper 拦下，**右键 → 打开 → 打开**即可放行；或运行：

\`\`\`bash
xattr -dr com.apple.quarantine /Applications/TrackMyMac.app
\`\`\`

App 启动后会引导你授予三项权限：辅助功能、输入监控、屏幕录制。每勾一项需要重启 App 生效。

完整说明见 [README](https://github.com/Halo-Welt/TrackMyMac#readme)。
EOF

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "==> Release $TAG already exists; uploading assets (overwrite)"
    gh release upload "$TAG" "$DMG" "$DMG_LATEST" --clobber
else
    echo "==> Creating release $TAG"
    gh release create "$TAG" "$DMG" "$DMG_LATEST" \
        --title "TrackMyMac ${VERSION}" \
        --notes-file "$NOTES_FILE"
fi
rm -f "$NOTES_FILE"

echo
echo "==> Done. View at: https://github.com/Halo-Welt/TrackMyMac/releases/tag/${TAG}"
