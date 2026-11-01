# Architecture and contracts

## Boundaries

Workspace data stays local; anonymous exchange-rate lookups are available independently of cloud. Cloud connection, synchronization and cloud backups are unavailable: Settings says so, no connection is restored and no background sync starts. The API endpoint is `https://api.timeit.mathislambert.fr`. The deployed API serves public GET `/v1/exchange-rate` and returns HTTP 501 with `CLOUD_NOT_AVAILABLE` on the other `/v1/*` routes; `/health` reports availability without connecting to PostgreSQL. `CLOUD_ENABLED=true` is permitted only for local backend development/tests and rejected in production. The contracts below describe the existing, unreleased cloud implementation.

The Mac owns immediate interaction and local persistence. `TimeitCore` contains portable models, deterministic calculations and the HTTP contract. `TimeitApp` owns platform services and observable UI state. The API owns authenticated access, shared persistence, optimistic concurrency and historical exchange-rate observations. PostgreSQL never accepts a user identity from request bodies; ownership comes from the verified token.

There are two runtime components: the native app and one HTTP service. No microservices, message broker, generic repository layer or placeholder iOS implementation.

## Application identity and updates

Stable, beta and nightly are subscriptions, not separate apps. Every release is `Timeit.app`, bundle ID `fr.mathislambert.Timeit`, with the same Application Support directory, preferences and Keychain identity. Never suffix these identities with a release channel.

Sparkle reads one signed feed at `https://timeit.mathislambert.fr/updates/appcast.xml`. Stable items have no channel; prereleases use Sparkle's native `beta` and `nightly` channels. The Settings subscription admits stable only, stable + beta, or all three. First launch defaults to the downloaded release's channel; the subscription survives every subsequent update. Changing the subscription does not migrate, copy or reset data.

All releases must use globally increasing numeric build numbers across every channel. Returning to Stable waits for a stable build newer than the installed build; there is no downgrade or custom version comparator. Database migrations must preserve data across this single release lineage. Never publish a nightly with a schema change that a later stable from an older branch cannot read.

Local builds do not start Sparkle. Official packaging must supply `TimeitUpdatesEnabled=true`, the Timeit Ed25519 public key in `SUPublicEDKey`, and `TimeitReleaseChannel`. Signed feeds and archives are required. The API is not involved in update discovery or installation.

## Local persistence

GRDB wraps SQLite. The workspace is stored as the same versioned JSON document the server receives, which keeps local and remote semantics identical. Four tables split it by how often each part changes:

- `workspace`: the document and its local version, rewritten on every edit (`saveEdit`).
- `sync`: revision, uploaded version, owner and the exact pending upload, rewritten by sync steps (`saveSync`).
- `rate`: one row per cached exchange rate (`saveRates`).
- `conflict`: backups of documents replaced while resolving a conflict.

Applying a remote document or resolving a conflict writes the document and sync rows in one transaction. The store is confined to the main actor; networking is asynchronous. A failed write leaves the visible workspace unchanged.

The JSON format is schema version 1. Newer unsupported schema versions fail explicitly. Add versioned migrations when evolving the wire format; do not silently reset data. Session start/end timestamps use ISO 8601 instants; account timezone determines report days and week boundaries.

## Synchronization

The app exchanges a complete personal workspace, with optimistic revision checks. This is appropriate for a small solo workspace and explicit occasional conflicts. The server limits payloads to 10 MiB / 20,000 entries. It is not a per-record incremental replication engine.

- GET `/v1/workspace`: `{ revision, document }`, null document for a new account.
- PUT `/v1/workspace`: `{ baseRevision, mutationID, document }`.
- A transaction-scoped advisory lock serializes writes by account, including first insertion.
- Every successful mutation has a receipt keyed by account + UUID and a payload hash. Repeating the request returns its original revision. Reusing the UUID for different content is rejected.
- The Mac persists the exact pending request before sending. A lost-response retry reuses it after restart. New local edits made during the request stay dirty after acknowledgment.
- A stale base revision returns HTTP 409. The app offers an explicit local/server choice and backs up the replaced document in SQLite's `conflicts` table.
- Authentication is bound to server URL + user subject so switching accounts cannot silently merge workspaces.
- Example workspaces never synchronize. Connection generations prevent stale network responses from replacing a newly selected workspace.

Deliberate boundary: conflict resolution replaces a document after user choice; it does not merge individual sessions automatically. PowerSync should be evaluated if incremental replication, shared workspaces or frequent concurrent editing become actual requirements. Avoid installing a replication platform solely to hide this explicit boundary.

## Money and time

Amounts and percentages are decimal strings on the wire. Swift uses Foundation Decimal and the server's FX normalization uses decimal.js. Durations are measured from persisted instants; a repeating UI timer is never the source of elapsed time. Reports clip sessions to the requested interval and split at local midnights, including 23/25-hour days. FX applies per work day before aggregation. Display rounding follows the selected currency; calculations retain decimal precision.

Starting another timer ends the current one at the same instant. The API rejects duplicate running timers, invalid references, duplicate IDs, future sessions, reversed dates, unknown timezones and combined deductions above 100%. Overlapping manual sessions remain visible rather than being silently altered.

The editable calendar lays events out by local wall-clock time and is optimized for ordinary work days; repeated/missing DST hours need a dedicated UI representation before overnight DST editing can be claimed complete. Drags snap to quarter hours and whole days through `CalendarMove`, and the grid draws the landing spot in the destination column before the move is saved. Financial duration calculations already use actual elapsed time.

## Exchange rates

GET `/v1/exchange-rate?base=USD&quote=EUR&date=YYYY-MM-DD` is public. The client sends only the pair and requested day, never an authentication token, project, amount or workspace. The existing service calls a fixed Frankfurter v2 URL with an eight-second timeout and validates the pair, calendar date and positive rate. Requested and observed dates stay separate, preserving weekend/holiday observations.

With cloud disabled, no PostgreSQL or identity provider is opened. The API keeps at most 2,048 observations in memory, deduplicates concurrent lookups and allows at most 16 outstanding provider requests. Capacity exhaustion returns 503 with Retry-After; unavailable or invalid provider data returns 502, never a fabricated rate. The server cache is disposable. The app persists its first accepted observation for each pair/day in the existing SQLite rate table, so cached calculations remain available offline and unchanged across server restarts. The unreleased cloud mode retains its existing PostgreSQL observation cache.

The app fetches missing rates on opening its window, after workspace edits or a currency change, when returning to the foreground, and every five minutes while the window is alive. Each pass requests at most 100 missing pair/days sequentially. Successful observations are persisted immediately without changing the workspace or sync metadata. Example workspaces never request rates; cancellation and workspace generations reject late responses. Unsupported pairs do not stop other currencies from resolving.

Until a required rate arrives, the dashboard and reports mark gross and net totals as incomplete, explain how many sessions are excluded, and offer Retry. A missing total is displayed as a dash instead of a misleading zero. Original currencies, amounts and durations are preserved.

## Identity and operations

Production uses OIDC Code + PKCE via AppAuth and secure Keychain persistence via Valet. API tokens are verified with jose against Keycloak's JWKS, issuer, audience and an allowed signing algorithm. Token claims and workspace bodies are not logged. Local DEV_AUTH is explicitly restricted to loopback outside production.

Deploy one API container behind Traefik and HTTPS. Use a dedicated PostgreSQL role/database and database backups. Provider setup, signing/notarization, production throttling, retention policy for receipts/conflict backups, account deletion/export and a deployment smoke test are required before opening this as a public service.
