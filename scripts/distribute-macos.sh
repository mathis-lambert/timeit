#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
: "${RELEASE_TAG:?}" "${BUILD_NUMBER:?}" "${APPLE_TEAM_ID:?}" "${APPLE_API_KEY_PATH:?}"
: "${APPLE_API_KEY_ID:?}" "${APPLE_API_ISSUER_ID:?}" "${SPARKLE_PUBLIC_ED_KEY:?}"
: "${SPARKLE_PRIVATE_KEY_FILE:?}" "${SIGNING_KEYCHAIN:?}"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' apps/macos/Info.plist)
CHANNEL=stable
if [[ "$RELEASE_TAG" == "v$VERSION" ]]; then
  CHANNEL=stable
elif [[ "$RELEASE_TAG" == "v$VERSION-beta."* && "${RELEASE_TAG##*-beta.}" =~ ^[1-9][0-9]*$ ]]; then
  CHANNEL=beta
elif [[ "$RELEASE_TAG" == "nightly-$(git rev-parse HEAD)" ]]; then
  CHANNEL=nightly
else
  echo 'Tag must match the app version, or identify this nightly commit.' >&2
  exit 1
fi
OUT="$ROOT/artifacts/distribution/$RELEASE_TAG"
[[ ! -e "$OUT" ]] || { echo 'Output directory already exists.' >&2; exit 1; }
mkdir -p "$OUT"
TIMEIT_DISTRIBUTION=true bash scripts/build-macos.sh release
APP="$ROOT/artifacts/Timeit.app"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $BUILD_NUMBER" "$PLIST"
/usr/libexec/PlistBuddy -c "Set TimeitReleaseChannel $CHANNEL" "$PLIST"
/usr/libexec/PlistBuddy -c 'Set TimeitUpdatesEnabled true' "$PLIST"
/usr/libexec/PlistBuddy -c "Add SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$PLIST"
IDENTITY=$(security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" | sed -nE "s/.*([A-F0-9]{40}).*Developer ID Application:.*\($APPLE_TEAM_ID\).*/\1/p")
[[ "$IDENTITY" =~ ^[A-F0-9]{40}$ ]] || { echo 'Expected one Developer ID Application identity for the configured team.' >&2; exit 1; }
sign() { codesign --force --sign "$IDENTITY" --keychain "$SIGNING_KEYCHAIN" --options runtime --timestamp "$1"; }
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
sign "$FRAMEWORK/Versions/B/Autoupdate"
sign "$FRAMEWORK/Versions/B/Updater.app"
sign "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
sign "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
sign "$FRAMEWORK"
for bundle in "$APP/Contents/Resources/"*.bundle; do sign "$bundle"; done
sign "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -verify_arch arm64 x86_64 "$APP/Contents/MacOS/Timeit"
xcrun dsymutil "$APP/Contents/MacOS/Timeit" -o "$OUT/Timeit.app.dSYM"
xcrun dwarfdump --uuid "$APP/Contents/MacOS/Timeit" | awk '{print $2,$3}' > "$OUT/binary-uuids.txt"
xcrun dwarfdump --uuid "$OUT/Timeit.app.dSYM" | awk '{print $2,$3}' > "$OUT/symbol-uuids.txt"
diff "$OUT/binary-uuids.txt" "$OUT/symbol-uuids.txt"
notarize() {
  local file="$1" name="$2" status=0
  xcrun notarytool submit "$file" --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER_ID" --wait --timeout 30m --output-format json > "$OUT/$name-notary.json" || status=$?
  local request
  request=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id", ""))' "$OUT/$name-notary.json")
  if [[ -n "$request" ]]; then
    xcrun notarytool log "$request" --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" \
      --issuer "$APPLE_API_ISSUER_ID" "$OUT/$name-notary-log.json"
  fi
  [[ "$status" == 0 ]]
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "Accepted"' "$OUT/$name-notary.json"
}
ditto -c -k --keepParent "$APP" "$OUT/submission.zip"
notarize "$OUT/submission.zip" app
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
syspolicy_check distribution "$APP"
rm "$OUT/submission.zip"
NAME="Timeit-$RELEASE_TAG"
ditto -c -k --keepParent "$APP" "$OUT/$NAME.zip"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Timeit.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Timeit -srcfolder "$STAGE" -ov -format UDZO "$OUT/$NAME.dmg"
sign "$OUT/$NAME.dmg"
notarize "$OUT/$NAME.dmg" dmg
xcrun stapler staple "$OUT/$NAME.dmg"
xcrun stapler validate "$OUT/$NAME.dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$OUT/$NAME.dmg"
ditto -c -k --keepParent "$OUT/Timeit.app.dSYM" "$OUT/$NAME.dSYM.zip"
rm -rf "$OUT/Timeit.app.dSYM"
(cd "$OUT" && shasum -a 256 "$NAME.zip" "$NAME.dmg" "$NAME.dSYM.zip" > SHA256SUMS)
python3 - "$OUT/release.json" "$RELEASE_TAG" "$VERSION" "$BUILD_NUMBER" "$CHANNEL" "$(git rev-parse HEAD)" <<'PY'
import json, sys
path, tag, version, build, channel, revision = sys.argv[1:]
with open(path, 'w') as stream:
    json.dump(dict(tag=tag, version=version, build=int(build), channel=channel, revision=revision), stream, indent=2)
    stream.write('\n')
PY
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'output=%s\nchannel=%s\n' "$OUT" "$CHANNEL" >> "$GITHUB_OUTPUT"
fi
