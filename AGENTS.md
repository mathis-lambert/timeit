# AGENTS.md

Timeit is a native macOS time tracker (`apps/macos`, Swift 6.2, macOS 26+) with an optional sync API (`backend`, TypeScript/Fastify/PostgreSQL). README.md covers setup for humans; this file covers how to work in the repo.

## Commands

```sh
# Mac app
swift build --package-path apps/macos
swift test --package-path apps/macos
swift format --in-place --recursive apps/macos/Sources apps/macos/Tests
swift format lint --recursive apps/macos/Sources apps/macos/Tests apps/macos/Package.swift scripts/make-icon.swift
bash scripts/build-macos.sh && open artifacts/Timeit.app --args --demo

# Live-window suite: screenshots + PDF + render-cost ceiling (needs a logged-in GUI session)
TIMEIT_RENDER_DIR="$PWD/artifacts/previews" swift test --package-path apps/macos --filter LiveWindowTests

# Backend
npm ci
npm run check && npm run build
docker compose up -d postgres
TEST_DATABASE_URL=postgres://timeit:timeit@127.0.0.1:54329/timeit npm test
```

Before finishing a change: format, lint, run the tests of every package you touched. For UI changes, also run the live-window suite and look at the captures.

## Layout and ownership

- `TimeitCore`: models, decimal money, finance, calendar layout, SQLite (GRDB), HTTP client. Must not import SwiftUI or AppKit.
- `TimeitApp`: `AppStore` (main-actor, `@Observable`) owns all workspace mutations and the rules views rely on (`nextTimerProject`, `canResume`, `recentResumable`, `visibleEntries`, `trackedSeconds`). Views call store methods, read those results, and never write to `LocalDatabase` directly. `Theme.swift` holds tokens, shared components and display helpers (`Display`, `displayTitle`, `label(forProject:)`). The accent is `Resources/Assets.xcassets/AccentColor`, copied into the app bundle by `scripts/build-macos.sh`.
- Period math lives in TimeitCore `Finance` (`segments`, `seconds`, `rateKey`, `summarize`); do not re-sum segments in views. Calendar drags snap through `CalendarMove`.
- `Commands.swift`: `AppShortcut` is the single table of in-app shortcuts (menus, palette, Settings); `AppStore.paletteCommands(matching:weekSeconds:)` and `perform(_:)` own the command palette.
- `LocalDatabase` writes narrowly: `saveEdit` for edits, `saveSync` for sync bookkeeping, `saveRates` for the rate cache, `save` only when document and sync change together.
- `backend/src`: one Fastify service. Ownership comes from the verified token, never from request bodies.
- `docs/ARCHITECTURE.md` explains sync, conflicts and money rules; read it before touching persistence, sync or finance.

## Conventions

- Swift: `.swift-format` (120 columns, 4 spaces). TypeScript and other files: `.editorconfig` (2 spaces).
- UI copy is French; code, comments, commits and docs are English.
- Amounts and percentages are decimal strings on the wire and `Decimal` in Swift. Never use `Double` for money.
- Durations derive from persisted instants. A UI timer is never the source of elapsed time.
- Follow `DESIGN.md`: native frame (window, sidebar, toolbar, menus, Settings), and inside the content only the components in `Components.swift` (`TimeitButtonStyle`, `timeitField`, `Combobox`, `DateTimeField`, `SegmentedControl`, `SwitchRow`, `Badge`, `ListRow`, `card()`); never a system `Picker` or `DatePicker` in the content. System text styles instead of point sizes; `Control` tokens and `Theme.accent` instead of ad hoc colors.
- Liquid Glass only through `glass(_:tint:radius:)` (`selection`, `panel`) in `Glass.swift`; never call `glassEffect` directly, never on content.
- Never add looping animations (`repeatForever`, repeating `symbolEffect`). They recomposite the whole glass window every frame; `runningTimerStaysCheapToRender` fails above 10 % CPU.
- `TimelineView` only where a value changes over time (running timer); finished rows render static text.

## Tests

- Swift Testing (`@Test`, `#expect`). Store tests use `AppStore(database: try LocalDatabase(), demo: true)`, an in-memory database.
- Tests that need a window server go in the serialized `LiveWindowTests` suite, gated by `TIMEIT_RENDER_DIR`.
- Backend integration tests skip without `TEST_DATABASE_URL` and create and drop their own schema.

## Boundaries

- Never commit `backend/.env` or any secret. `backend/.env.example` is the documented template.
- Never write to the real workspace at `~/Library/Application Support/Timeit/`; use the demo mode or an in-memory database.
- Do not deploy, push or change remote infrastructure unless asked.
- Do not change the wire format or SQLite schema without a versioned migration (schema version 1 today).
- `artifacts/` is build output and stays untracked. Curated screenshots go in `docs/screenshots/`.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/): `type(scope): summary` in the imperative, lowercase, no trailing period, at most 72 characters. Types: `feat`, `fix`, `perf`, `refactor`, `style`, `test`, `docs`, `build`, `ci`, `chore`. Scopes: `macos`, `backend`, `design`, `docs`, `ci`. Explain the why in the body when it isn't obvious.
