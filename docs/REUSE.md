# Reuse decisions

Verified 2026-10-20 against upstream repositories, manifests, licenses and public documentation. Four Frankfurter historical conversions were also called successfully (USD, JPY, KWD, XOF → EUR). Live Google/Apple login was not performed.

## Included

| Component | Responsibility | License |
| --- | --- | --- |
| [GRDB 7.11.1](https://github.com/groue/GRDB.swift) | SQLite transactions and migrations | MIT |
| [AppAuth 3.0.0](https://github.com/openid/AppAuth-iOS) | Native OAuth/OIDC, PKCE, token refresh | Apache-2.0 |
| [Valet 5.1.1](https://github.com/square/Valet) | macOS Keychain | Apache-2.0 |
| [KeyboardShortcuts 3.1.0](https://github.com/sindresorhus/KeyboardShortcuts) | Configurable global shortcut and recorder | MIT |
| [Fastify](https://github.com/fastify/fastify) | HTTP server, JSON Schema validation and structured logs | MIT |
| [TypeBox](https://github.com/sinclairzx81/typebox) | One source for JSON Schema and TypeScript input types | MIT |
| [jose](https://github.com/panva/jose) | JWT/JWKS verification | MIT |
| [node-postgres](https://github.com/brianc/node-postgres) | PostgreSQL driver | MIT |
| [decimal.js](https://github.com/MikeMcl/decimal.js) | Decimal normalization | MIT |
| [Frankfurter](https://frankfurter.dev/) | Historical FX observations | Free public API; caching allowed |

Native frameworks: SwiftUI/AppKit for UI, Charts for charts, Foundation for dates/currencies/Decimal/networking, TabularData for CSV, AppKit for PDF printing, ServiceManagement for launch at login. Native SF fonts and SF Symbols are supplied by the operating system. There are no paid API dependencies. Native dependency license notices are copied into the app's Resources/Licenses folder by the packaging script.

Foundation supplies currency selection; Frankfurter supplies conversions for its supported pairs/dates. At research time its public v2 catalog returned 165 currencies, while broader advertised coverage included historical currencies. Unsupported or unavailable observations leave totals visibly incomplete.

## Evaluated, not included

- [PowerSync](https://github.com/powersync-ja/powersync-swift): native macOS support and ARM64 server image verified. Swift SDK Apache-2.0; server FSL-1.1-ALv2. GRDB adapter is alpha, including schema-update limitations. Keep as an incremental-sync candidate; do not mix its experimental GRDB adapter into the app.
- [SwiftUiCalendarKit](https://github.com/Haskins-io/SwiftUiCalendarKit): MIT and macOS-compatible, but drag/drop and resizing remain on its ToDo list. The implemented weekly editor needs those interactions, so it uses a focused SwiftUI grid and Foundation Calendar instead.
- [richardtop/CalendarKit](https://github.com/richardtop/CalendarKit): UIKit-oriented; its package targets iOS/tvOS, not a native AppKit macOS target.
- [Kimai](https://www.kimai.org/): AGPL time-tracking backend with API/Keycloak SAML support. Customer-level currency model does not match the requested project-level model directly.
- [solidtime](https://www.solidtime.io/roadmap): AGPL backend; multiple currencies and OIDC were still on the roadmap when checked. Documented rate changes can affect existing time entries.
- [Urssaf Mon-entreprise API](https://mon-entreprise.urssaf.fr/d%C3%A9veloppeur/api): valuable for optional French regulatory simulations; account-level configurable estimates remain country-neutral.
- [Sparkle](https://sparkle-project.org/): appropriate for a future signed direct distribution, not needed for local bundle generation.
- [Swift OpenAPI Generator](https://github.com/apple/swift-openapi-generator): appropriate once the API is stabilized. The current wire contract is small; no generated client infrastructure is included yet.
- EventKit / App Intents / WidgetKit: suitable native integrations for later slices. The internal calendar does not request access to personal calendar data.
