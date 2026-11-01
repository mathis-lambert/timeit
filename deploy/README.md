# Timeit deployment

GitHub Actions owns builds. The VPS only pulls immutable GHCR images and runs Compose; it has no checkout, backend sources, Node toolchain or build context for Timeit.

## Runtime layout

`/opt/mathislambert.fr/applications/timeit/` contains:

```text
compose.prod.yaml
deploy.sh
.env                 # deployed image digests, no application secrets
.deploy.lock
updates/             # persistent signed appcast, never replaced by deployment
```

The two images are `ghcr.io/mathis-lambert/timeit-api` and `ghcr.io/mathis-lambert/timeit-releases`. Both support linux/amd64 and linux/arm64. Nginx configuration is part of the releases image. Compose joins the existing external Traefik `proxy` network without changing shared infrastructure or GetAero.

- `api.timeit.mathislambert.fr`: Fastify. `/health` returns 200 and `cloudAvailable: false`; `/v1/*` returns 501 `CLOUD_NOT_AVAILABLE`. No database or identity credentials are needed. Production refuses to enable the unfinished cloud service.
- `timeit.mathislambert.fr/updates/appcast.xml`: signed Sparkle feed, mounted read-only. Absent feeds return 404. `/healthz` is the health endpoint; other paths, including `/`, return 404 until the presentation site is built.

## CI and deployment

`.github/workflows/ci.yml` runs backend tests with PostgreSQL and Swift tests/lint. Only successful checks on `main` permit image publication. Images carry the source SHA tag and source-repository label; deployments use their immutable digests, never a mutable `latest` tag. Pull requests cannot publish or deploy. Workflow concurrency and a server-side lock prevent overlapping deployment operations.

The `PROD` GitHub environment uses the same secret naming as GetAero:

- `ML_DEPLOY_HOST`, `ML_DEPLOY_USER`, `ML_DEPLOY_PORT`
- `ML_DEPLOY_KEY`, `ML_DEPLOY_KNOWN_HOSTS`

The repository variable `TIMEIT_AUTO_DEPLOY=true` enables automatic deployment. The SSH user must be able to write this application's directory and operate Docker. The registry login uses the workflow's short-lived `GITHUB_TOKEN`; its Docker credential directory is deleted at exit. Do not put a GitHub token in `.env`.

CI uploads only `compose.prod.yaml` and `deploy.sh`. The script pulls both images before replacing containers, waits for health, and records the digests in `.env` only after success. On failure, an existing `.env` restores the preceding deployment. Public HTTPS health and the disabled cloud response are then checked.

For an intentional manual deployment or rollback, upload these same two runtime files and pipe an authorized GHCR read token into:

```sh
bash deploy.sh \
  ghcr.io/mathis-lambert/timeit-api@sha256:<digest> \
  ghcr.io/mathis-lambert/timeit-releases@sha256:<digest> \
  <github-user>
```

Never run builds or clone this repository on the VPS. Do not prune other applications' images or Docker build caches when cleaning Timeit.

## Mac releases are separate

Installer/ZIP publication and the signed appcast will use GitHub Releases. The container workflow does not publish Mac releases. Serving the update URL and integrating Sparkle do not validate signed installation or replacement; that requires the signing/notarization workflow and two real signed releases.

Publish one signed appcast atomically, preserving all three native Sparkle channels: omit `sparkle:channel` for stable, use `beta` or `nightly` for prereleases. Build numbers must increase globally across channels, including promotion of the same source revision from beta to stable. Never fabricate a feed before the first signed release. Use a Timeit-specific signing key and a restricted feed publisher, separate from the container deployment credential.
