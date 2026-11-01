#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${RELEASE_TAG:?}" "${SPARKLE_PRIVATE_KEY_FILE:?}" "${GH_TOKEN:?}"
: "${DEPLOY_HOST:?}" "${DEPLOY_USER:?}" "${DEPLOY_PORT:?}"
TOOLS="$ROOT/apps/macos/.build/artifacts/sparkle/Sparkle/bin"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/feed"
gh release download "$RELEASE_TAG" --repo mathis-lambert/timeit --pattern release.json --dir "$WORK"
CHANNEL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["channel"])' "$WORK/release.json")
BUILD=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"])' "$WORK/release.json")
[[ "$CHANNEL" == stable || "$CHANNEL" == beta || "$CHANNEL" == nightly ]]
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]]
BASE="https://github.com/mathis-lambert/timeit/releases/download/$RELEASE_TAG"
# Download the public asset, not an authenticated draft: subscribers must be able to fetch it.
curl --fail --location --silent --show-error --retry 5 --retry-all-errors "$BASE/Timeit-$RELEASE_TAG.zip" -o "$WORK/feed/Timeit-$RELEASE_TAG.zip"
STATUS=$(curl --silent --show-error --retry 3 -o "$WORK/previous.xml" -w '%{http_code}' https://timeit.mathislambert.fr/updates/appcast.xml)
if [[ "$STATUS" == 200 ]]; then
  "$TOOLS/sign_update" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" --verify "$WORK/previous.xml"
  cp "$WORK/previous.xml" "$WORK/feed/appcast.xml"
elif [[ "$STATUS" != 404 ]]; then
  echo "Cannot read existing appcast: HTTP $STATUS" >&2
  exit 1
else
  rm "$WORK/previous.xml"
fi
ARGS=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" --download-url-prefix "$BASE/" --maximum-versions 0 --maximum-deltas 0)
if [[ "$CHANNEL" != stable ]]; then ARGS+=(--channel "$CHANNEL"); fi
"$TOOLS/generate_appcast" "${ARGS[@]}" "$WORK/feed"
"$TOOLS/sign_update" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" --verify "$WORK/feed/appcast.xml"
python3 - "$ROOT/deploy/publish-appcast.py" "$WORK" "$BUILD" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location('publisher', sys.argv[1])
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
work = pathlib.Path(sys.argv[2])
previous = work / 'previous.xml'
incoming = (work / 'feed/appcast.xml').read_bytes()
publisher.validate_update(previous.read_bytes() if previous.exists() else None, incoming)
assert int(sys.argv[3]) in publisher.entries(incoming), 'Release build missing from appcast'
PY
TARGET="$DEPLOY_USER@$DEPLOY_HOST"
DESTINATION=/opt/mathislambert.fr/applications/timeit
scp -P "$DEPLOY_PORT" -o BatchMode=yes -o StrictHostKeyChecking=yes "$ROOT/deploy/publish-appcast.py" "$TARGET:$DESTINATION/publish-appcast.py"
ssh -p "$DEPLOY_PORT" -o BatchMode=yes -o StrictHostKeyChecking=yes "$TARGET" \
  "python3 $DESTINATION/publish-appcast.py" < "$WORK/feed/appcast.xml"
curl --fail --silent --show-error https://timeit.mathislambert.fr/updates/appcast.xml -o "$WORK/published.xml"
cmp "$WORK/feed/appcast.xml" "$WORK/published.xml"
