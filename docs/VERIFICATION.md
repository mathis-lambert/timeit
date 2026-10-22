# Verification

## Automated checks

Executed on macOS 27.0.1, Xcode 27.1, Swift 6.4 and Node 26.9.0 with local PostgreSQL 17.6 in Docker.

- Backend TypeScript check and production build passed.
- Backend integration suite: 9 tests passed with no skips. Real PostgreSQL transactions and real signed JWTs with a local JWKS server. External FX responses are controlled fixtures in this suite; public FX connectivity was checked separately during research.
- Swift core suite: 9 tests passed. Covers exact amounts, separate deductions, rate snapshots, missing rates, midnight/period clipping, DST elapsed time, overlap layout, SQLite persistence, explicit null encoding of a running timer and persisted idempotent-upload retries while newer edits stay dirty.
- Swift app store: 6 tests passed. Covers disposable demo isolation, project switching stopping the old timer and persisting the new one, delete/undo preserving the snapshot, archiving retaining history, resume suggestions skipping the running and archived projects, and the next-timer project fallback.
- Native HTTP contract: passed separately using URLSession against a real Fastify listener and temporary PostgreSQL schema. Covers configuration, identity, a running timer with explicit null, fractional timestamps, exact currency precision, upload/read, retry, 409 conflicts and identity FX. This opt-in test is skipped by the ordinary Swift command and run through `npm run test:native -w backend`.
- Live-window suite (opt-in with `TIMEIT_RENDER_DIR`, serialized): passed. Liquid Glass only draws in a live window, so each view is shown in a floating window and captured with `screencapture` (light/dark dashboard, running timer, calendar, projects, reports, command palette, menu-bar panel, two editors). `runningTimerStaysCheapToRender` keeps a running timer under 10 % process CPU on the dashboard and calendar; measured 0.6 % and 0.2 %, down from 50 % and 103 % before looping effects were removed.
- Swift formatter lint passed with the checked-in configuration. Info.plist validation passed.
- Docker image `timeit-backend:local` built successfully. Runtime imports also passed inside the image using Node 24 Alpine. Image excludes environment files, tests and development dependencies.
- Native app compilation and bundle packaging passed. Runtime checking caught a reentrant update loop caused by TimelineView in the menu-bar label. Replaced with a static status symbol; the live timer remains inside the panel. The corrected debug process remained running for over eight minutes, at 0% sampled idle CPU and approximately 28 MiB RSS at the last observation. This is an idle smoke check, not a benchmark.
- Final optimized release build passed, as did repeated bundle assembly and `codesign --verify --deep --strict`. Dependency resources and four upstream license files are included. The packaging script handles read-only upstream license files on subsequent builds.
- Local development backend started successfully; `/health` returned `ok` and `/v1/config` confirmed loopback development authentication. No production server was deployed.

## Visual review and remaining manual checks

Inspected live captures of every screen in dark and light after the de-slop pass. Captures come from non-key windows, so prominent glass buttons render in their inactive grey there; in the active app they use the accent.

Calendar drag/resize (including the dragged event staying above other day columns), the command palette's keyboard navigation, save panels, login-at-startup and VoiceOver were not exercised by automated clicks and remain manual checks.

Live-window captures are written to `$TIMEIT_RENDER_DIR`; curated copies live in `docs/screenshots/`. Their fictional workspace never touches the real local database.

## Boundaries

- Production Google/Apple provider login and VPS deployment have not been performed.
- Local bundles are ad-hoc signed, not notarized.
- No claim of complete VoiceOver or accessibility certification. Labels and native controls are implemented; screen-reader testing remains a separate check.
- Deployment target is macOS 26 (Liquid Glass APIs). Runtime checked on macOS 27 only.
