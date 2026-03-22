#!/usr/bin/env bash
# Capture a real window/screen after launching a local Release build (requires a GUI session).
# Output: docs/images/main-window-real.png
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcodebuild -scheme RLeon -configuration Release -destination 'platform=macOS' build -quiet
APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" -name 'RLeon.app' -path '*Release*' 2>/dev/null | head -1)"
if [[ -z "${APP}" ]]; then
  echo "RLeon.app (Release) not found under DerivedData."
  exit 1
fi
open -a "$APP"
sleep 4
osascript -e 'tell application "System Events" to tell process "RLeon" to set frontmost to true' || true
sleep 1
mkdir -p "$ROOT/docs/images"
OUT="$ROOT/docs/images/main-window-real.png"
screencapture -x "$OUT"
osascript -e 'quit app "RLeon"' || true
echo "Wrote $OUT"
