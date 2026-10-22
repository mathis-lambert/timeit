#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"
swift build --package-path "$ROOT/apps/macos" --configuration "$CONFIGURATION"
BIN="$(swift build --package-path "$ROOT/apps/macos" --configuration "$CONFIGURATION" --show-bin-path)"
APP="$ROOT/artifacts/Timeit.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Timeit" "$APP/Contents/MacOS/Timeit"
cp "$ROOT/apps/macos/Info.plist" "$APP/Contents/Info.plist"
for bundle in "$BIN/"*.bundle; do
  if [[ -d "$bundle" ]]; then cp -R "$bundle" "$APP/Contents/Resources/"; fi
done
LICENSES="$APP/Contents/Resources/Licenses"
mkdir -p "$LICENSES"
for dependency in GRDB.swift AppAuth-iOS Valet; do
  install -m 644 "$ROOT/apps/macos/.build/checkouts/$dependency/LICENSE" "$LICENSES/$dependency.txt"
done
install -m 644 "$ROOT/apps/macos/.build/checkouts/KeyboardShortcuts/license" "$LICENSES/KeyboardShortcuts.txt"
if [[ ! -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
  mkdir -p "$ROOT/artifacts/AppIcon.iconset"
  swift "$ROOT/scripts/make-icon.swift" "$ROOT/artifacts/AppIcon.iconset"
  iconutil -c icns "$ROOT/artifacts/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --deep --sign - "$APP"
printf '%s\n' "$APP"
