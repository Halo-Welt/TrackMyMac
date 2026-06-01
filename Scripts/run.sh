#!/usr/bin/env bash
# Convenience: build (if needed) then open the app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/dist/TrackMyMac.app"
if [ ! -d "$APP" ]; then
    bash "$ROOT/Scripts/build_app.sh"
fi
open "$APP"
