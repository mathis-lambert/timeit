#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
api_image="${1:?Missing API image digest}"
releases_image="${2:?Missing releases image digest}"
registry_user="${3:?Missing registry user}"
[[ "$api_image" =~ ^ghcr\.io/mathis-lambert/timeit-api@sha256:[a-f0-9]{64}$ ]]
[[ "$releases_image" =~ ^ghcr\.io/mathis-lambert/timeit-releases@sha256:[a-f0-9]{64}$ ]]

# Only runtime files live here. The feed survives every image deployment.
if [[ ! -d updates ]]; then install -d -m 755 updates; fi
exec 9>.deploy.lock
flock 9
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export DOCKER_CONFIG="$work/docker"
mkdir -m 700 "$DOCKER_CONFIG"
docker login ghcr.io --username "$registry_user" --password-stdin
printf 'TIMEIT_API_IMAGE=%s\nTIMEIT_RELEASES_IMAGE=%s\n' "$api_image" "$releases_image" > "$work/release.env"
compose=(docker compose --env-file "$work/release.env" -f compose.prod.yaml)
"${compose[@]}" config --quiet
"${compose[@]}" pull
if ! "${compose[@]}" up -d --wait --wait-timeout 120; then
    if [[ -f .env ]]; then
        docker compose --env-file .env -f compose.prod.yaml up -d --wait --wait-timeout 120
    fi
    exit 1
fi
install -m 644 "$work/release.env" .env.next
mv .env.next .env
