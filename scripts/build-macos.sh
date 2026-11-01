#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"
# Xcode compiles asset catalogs and gives Bundle.module its application resource layout.
BUILD=(--package-path "$ROOT/apps/macos" --configuration "$CONFIGURATION" --build-system xcode)
if [[ "${TIMEIT_DISTRIBUTION:-false}" == true ]]; then
  BUILD+=(--arch arm64 --arch x86_64 -Xswiftc -g)
fi
swift build "${BUILD[@]}"
BIN="$(swift build "${BUILD[@]}" --show-bin-path)"
APP="$ROOT/artifacts/Timeit.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Timeit" "$APP/Contents/MacOS/Timeit"
cp "$ROOT/apps/macos/Info.plist" "$APP/Contents/Info.plist"
SPARKLE="$ROOT/apps/macos/.build/artifacts/sparkle/Sparkle"
ditto "$SPARKLE/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
for bundle in "$BIN/"*.bundle; do
  if [[ -d "$bundle" ]]; then cp -R "$bundle" "$APP/Contents/Resources/"; fi
done
# The app's own catalog must sit in the main bundle for NSAccentColorName to reach native controls.
cp "$BIN/Timeit_TimeitApp.bundle/Contents/Resources/Assets.car" "$APP/Contents/Resources/Assets.car"
LICENSES="$APP/Contents/Resources/Licenses"
mkdir -p "$LICENSES"
for dependency in GRDB.swift AppAuth-iOS Valet; do
  install -m 644 "$ROOT/apps/macos/.build/checkouts/$dependency/LICENSE" "$LICENSES/$dependency.txt"
done
install -m 644 "$ROOT/apps/macos/.build/checkouts/KeyboardShortcuts/license" "$LICENSES/KeyboardShortcuts.txt"
install -m 644 "$SPARKLE/LICENSE" "$LICENSES/Sparkle.txt"
if [[ ! -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
  mkdir -p "$ROOT/artifacts/AppIcon.iconset"
  swift "$ROOT/scripts/make-icon.swift" "$ROOT/artifacts/AppIcon.iconset"
  iconutil -c icns "$ROOT/artifacts/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
fi
if [[ "${TIMEIT_DISTRIBUTION:-false}" != true ]]; then
  codesign --force --deep --sign - "$APP"
fi
printf '%s\n' "$APP"
