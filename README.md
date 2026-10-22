# Timeit

A native macOS time tracker for independent professionals: a SwiftUI window and menu-bar companion, offline SQLite storage, clients and projects, an editable weekly calendar, historical hourly rates, multi-currency estimates with separate social contributions and income tax, and CSV/PDF exports. An optional TypeScript API synchronizes the workspace across Macs.

![Dashboard](docs/screenshots/dashboard-dark.png)

| Calendar | Command palette | Menu bar |
| --- | --- | --- |
| ![Calendar](docs/screenshots/calendar.png) | ![Command palette](docs/screenshots/command-palette.png) | ![Menu bar](docs/screenshots/menu-bar.png) |

## Repository

```text
apps/macos/                 Swift package (macOS 26+)
  Sources/TimeitCore/       Models, money, calendar layout, SQLite, API client (no UI frameworks)
  Sources/TimeitApp/        SwiftUI/AppKit app, authentication, features
  Tests/                    Core, store and opt-in live-window tests
backend/                    TypeScript HTTP API (Fastify, PostgreSQL)
  src/auth/                 OIDC access-token verification
  src/db/                   PostgreSQL setup and transactional migrations
  src/workspace/            Validation and versioned workspace persistence
  src/exchange/             Historical FX lookup and immutable cache
scripts/                    App bundle packaging and icon source
docs/                       Architecture, dependency choices, verification, screenshots
DESIGN.md                   Design system and interaction rules
AGENTS.md                   Instructions for coding agents
```

## Run the Mac app

Requirements: macOS 26+, Xcode 26+ (Swift 6.2+). Open `apps/macos/Package.swift` in Xcode, or build from the terminal:

```sh
bash scripts/build-macos.sh          # add "release" for an optimized build
open artifacts/Timeit.app
```

The script produces an ad-hoc signed local bundle in `artifacts/`. Developer ID signing, notarization and automatic updates are not configured yet.

To look around without touching your data, choose **Explorer un exemple** on the welcome screen (or launch with `--demo`). The example workspace lives in memory only; **Revenir à mon espace** goes back to your real workspace.

Local data: `~/Library/Application Support/Timeit/timeit.sqlite`.

### Keyboard

| Shortcut | Action |
| --- | --- |
| ⌘K | Command palette: filter projects and actions, ↑↓ to move, Return to run |
| ⌘↩ | Start or stop the timer (a global shortcut is configurable in Settings) |
| ⌘N / ⌘⇧N | New session / new project |
| ⌘Z | Undo a deleted session |

In the calendar, drag across empty time to draw a session (or double-click to add one), drag an event to move it and drag its bottom edge to resize it. Every drag has a form alternative. Closing the window keeps the menu-bar app running.

## Run the backend locally

Requirements: Node.js 24+, npm, Docker Compose (or PostgreSQL 17+).

```sh
npm ci
docker compose up -d postgres
cp backend/.env.example backend/.env
npm run dev
```

The API listens on `http://127.0.0.1:4318`. In the app, open Settings → Cloud and connect to that address. The local development identity needs no account and is refused outside loopback or in production. Migrations run before the server starts. The Compose credentials are for local development only.

## Production identity and hosting

The API verifies Keycloak access tokens against its JWKS, issuer and audience. Set `OIDC_ISSUER`, `OIDC_AUDIENCE`, `OIDC_CLIENT_ID`, `DATABASE_URL`, `NODE_ENV=production` and `DEV_AUTH=false`. Register a public native OIDC client (Authorization Code + PKCE) with this redirect URI:

```text
fr.mathislambert.timeit:/oauth/callback
```

The app uses AppAuth for discovery, PKCE and refresh, and stores the auth state in the Keychain through Valet. Google and Apple sign-in are configured on the identity server; they have not been verified against a live deployment yet.

`backend/Dockerfile` builds the API from the repository root. Run it behind HTTPS with a dedicated PostgreSQL database and role, and set up backups before opening registrations.

## Checks

```sh
npm run check && npm run build
TEST_DATABASE_URL=postgres://timeit:timeit@127.0.0.1:54329/timeit npm test
swift test --package-path apps/macos
swift format lint --recursive apps/macos/Sources apps/macos/Tests apps/macos/Package.swift scripts/make-icon.swift
```

Optional checks that need more setup:

```sh
# Real Swift HTTP client against an isolated backend schema
TEST_DATABASE_URL=postgres://timeit:timeit@127.0.0.1:54329/timeit npm run test:native -w backend
# Live-window suite (needs a logged-in session): screenshots, PDF export, render-cost ceiling
TIMEIT_RENDER_DIR="$PWD/artifacts/previews" swift test --package-path apps/macos --filter LiveWindowTests
```

Integration tests create and drop their own PostgreSQL schema and skip when `TEST_DATABASE_URL` is unset. `docs/VERIFICATION.md` records what has been checked and what remains manual.

## Financial meaning

"Honoraires bruts" is the value of billable work before deductions, excluding VAT. It is not cash received. "Net estimé" subtracts two configurable percentages, both applied to gross fees; it is not a country-specific tax calculation.

Each session stores its own currency, rate and deduction percentages, so changing a project or account rate never rewrites history. Foreign amounts stay unconverted until the historical rate for that day is available, and a missing rate is shown as such, never treated as 1:1. Conversions come from Frankfurter and cover the pairs and dates it supports.

## Further reading

- `docs/ARCHITECTURE.md`: data ownership, synchronization, conflicts and limits
- `docs/REUSE.md`: dependency choices and licenses
- `DESIGN.md`: design system, motion and performance rules
