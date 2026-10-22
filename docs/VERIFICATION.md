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

- Google and Apple sign-in and a production deployment have not been exercised.
- Local bundles are ad-hoc signed, not notarized.
- The deployment target is macOS 26; the app has only been run on macOS 27.
