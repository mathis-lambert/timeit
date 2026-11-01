# Verification

What each check covers, and what still needs a person. Commands are in `AGENTS.md`.

## Automated

- **Swift core** (`TimeitCoreTests`): exact decimal amounts, separate deductions, rate snapshots and missing rates, midnight and period clipping, DST elapsed time, calendar overlap layout, quarter-hour snapping of drags and drawn sessions, SQLite round trips, writes that touch only their own table, explicit `null` for a running timer, and idempotent upload retries while newer edits stay dirty.
- **Swift store** (`AppStoreTests`): disposable demo isolation, project switching that stops the previous timer, delete and undo, archiving that keeps history, resume suggestions, the next-timer project fallback, and command-palette filtering and execution.
- **Live window** (`LiveWindowTests`, opt-in with `TIMEIT_RENDER_DIR`, serialized): every screen captured from a real floating window (Liquid Glass does not draw offscreen), PDF export checked with PDFKit, and `runningTimerStaysCheapToRender`, which fails if a running timer keeps the dashboard or calendar above 10 % process CPU.
- **Native HTTP contract** (`APIContractTests`, opt-in through `npm run test:native -w backend`): the real Swift client against a Fastify listener and a temporary PostgreSQL schema, covering configuration, identity, running timers, fractional timestamps, decimal precision, upload and retry, 409 conflicts and identity FX.
- **Backend** (`backend/test`): configuration rules, and integration tests with real PostgreSQL transactions and signed JWTs from a local JWKS. FX provider responses are fixtures.
- **Formatting and types**: `swift format lint`, `npm run check`.

## Manual

Captures come from non-key windows, so prominent glass buttons render grey there; in the active app they use the accent.

Not covered by automation: calendar drawing, drag, resize and their previews; keyboard navigation in the command palette; save panels; launch at login; the global shortcut; VoiceOver.

## Boundaries

- Google and Apple sign-in have not been exercised. The production API is deployed with cloud routes disabled (501).
- Local development bundles are ad-hoc signed. Published releases use notarized Developer ID signatures.
- The deployment target is macOS 26; the app has only been run on macOS 27.

## Channel and cloud availability checks (2026-11-01)

- Update tests cover native channel eligibility, subscription persistence across release metadata changes, unchanged workspace data, and disabled/invalid updater configuration. Local builds never start Sparkle.
- Store tests call connection restoration, connection and synchronization while cloud is unavailable. Backend tests exercise every cloud route and multiple HTTP methods without PostgreSQL, expecting 501, and reject enabling cloud in production.
- Live-window previews include Stable and Nightly update settings.
- Distribution now uses Developer ID signing, notarization, a single signed multi-channel appcast and globally increasing build numbers. Real update/restart tests between two signed builds remain required. Changing a channel must never force an older build or discard a running timer.

## Distribution pipeline checks (2026-11-01)

- Universal release packaging built successfully on the local Xcode toolchain;
  both Intel and Apple Silicon binaries declare macOS 26.0 as their minimum.
- Generated dSYM UUIDs match both executable architectures.
- The official Sparkle tools generated and verified a signed test feed, retaining
  the beta entry when a newer stable entry was added. These local fixture builds
  are not public releases and are only ad-hoc signed.
- Publisher tests cover preserved channels, stale builds, conflicting duplicate
  builds, atomic writes and idempotent retries. Workflow syntax is linted.
- `v0.1.0-beta.1` (build 3) is published. Apple accepted both the app and DMG.
  Downloaded GitHub assets passed SHA-256, nested signature verification, stapled
  ticket validation and Gatekeeper (`Notarized Developer ID`). The public appcast
  signature verified successfully with the Timeit key.
- A real Sparkle update/relaunch between two signed builds remains to be exercised
  in a disposable macOS account. See `RELEASES.md`.

## Public exchange rates (2026-11-01)

- Backend fixtures cover anonymous access without PostgreSQL, observed dates for
  weekends, cache reuse, invalid provider data, concurrent deduplication and bounded
  provider concurrency. Cloud routes still return 501.
- Store tests cover persisted offline rates, unchanged workspace/sync metadata,
  partial failures and retries, late responses after entering demo, and progress
  past an unavailable page in a long history.
- The real Swift HTTP client is tested against the production-configured Fastify
  app with a fixture provider; the server rejects any Authorization header.
- Live-window captures include the incomplete-total notice. Both window tests,
  including the render-cost ceiling, passed. No real user workspace was opened.
- The appcast publisher was executed from shell-quoted source with the signed feed
  streamed on stdin; the resulting bytes matched exactly, without a deployed script.
