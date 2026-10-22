# Architecture and contracts

## Boundaries

The Mac owns immediate interaction and local persistence. `TimeitCore` contains portable models, deterministic calculations and the HTTP contract. `TimeitApp` owns platform services and observable UI state. The API owns authenticated access, shared persistence, optimistic concurrency and historical exchange-rate observations. PostgreSQL never accepts a user identity from request bodies; ownership comes from the verified token.

There are two runtime components: the native app and one HTTP service. No microservices, message broker, generic repository layer or placeholder iOS implementation.

## Local persistence

GRDB wraps SQLite transactions and schema migrations. The MVP saves a versioned JSON workspace and sync metadata atomically in SQLite. This deliberately keeps local and remote document semantics identical. FX cache and pending mutations are saved alongside the document. The store is confined to the main actor; expensive networking is asynchronous. Failed writes do not update the visible workspace.

The JSON format is schema version 1. Newer unsupported schema versions fail explicitly. Add versioned migrations when evolving the wire format; do not silently reset data. Session start/end timestamps use ISO 8601 instants; account timezone determines report days and week boundaries.

## Synchronization

The first MVP exchanges a complete personal workspace, with optimistic revision checks. This is appropriate for a small solo workspace and explicit occasional conflicts. The server limits payloads to 10 MiB / 20,000 entries. It is not a per-record incremental replication engine.

- GET `/v1/workspace`: `{ revision, document }`, null document for a new account.
- PUT `/v1/workspace`: `{ baseRevision, mutationID, document }`.
- A transaction-scoped advisory lock serializes writes by account, including first insertion.
- Every successful mutation has a receipt keyed by account + UUID and a payload hash. Repeating the request returns its original revision. Reusing the UUID for different content is rejected.
- The Mac persists the exact pending request before sending. A lost-response retry reuses it after restart. New local edits made during the request stay dirty after acknowledgment.
- A stale base revision returns HTTP 409. The app offers an explicit local/server choice and backs up the replaced document in SQLite's `conflicts` table.
- Authentication is bound to server URL + user subject so switching accounts cannot silently merge workspaces.
- Example workspaces never synchronize. Connection generations prevent stale network responses from replacing a newly selected workspace.

Deliberate boundary: conflict resolution replaces a document after user choice; it does not merge individual sessions automatically. PowerSync should be evaluated if incremental replication, shared workspaces or frequent concurrent editing become actual requirements. Avoid installing a replication platform solely to hide this explicit first-version boundary.

## Money and time

Amounts and percentages are decimal strings on the wire. Swift uses Foundation Decimal and the server's FX normalization uses decimal.js. Durations are measured from persisted instants; a repeating UI timer is never the source of elapsed time. Reports clip sessions to the requested interval and split at local midnights, including 23/25-hour days. FX applies per work day before aggregation. Display rounding follows the selected currency; calculations retain decimal precision.

Starting another timer ends the current one at the same instant. The API rejects duplicate running timers, invalid references, duplicate IDs, future sessions, reversed dates, unknown timezones and combined deductions above 100%. Overlapping manual sessions remain visible rather than being silently altered.

The editable calendar lays events out by local wall-clock time. Its first version is optimized for ordinary work days; repeated/missing DST hours need a dedicated UI representation before overnight DST editing can be claimed complete. Financial duration calculations already use actual elapsed time.

## Exchange rates

GET `/v1/exchange-rate?base=USD&quote=EUR&date=YYYY-MM-DD` requires authentication. It calls a fixed Frankfurter URL with a timeout, verifies the pair/date/positive rate, and stores the first accepted observation. Store both requested date and provider date, preserving weekends/holidays. Historical cache values do not silently change after a provider correction. No provider secret or client business data is sent to Frankfurter.

The client fetches missing rates after sync, at most 100 per pass, without blocking local recording. First-version rate access requires the backend connection. Foreign sessions work offline, but their converted totals remain partial until rates arrive.

## Identity and operations

Production uses OIDC Code + PKCE via AppAuth and secure Keychain persistence via Valet. API tokens are verified with jose against Keycloak's JWKS, issuer, audience and an allowed signing algorithm. Token claims and workspace bodies are not logged. Local DEV_AUTH is explicitly restricted to loopback outside production.

Deploy one API container behind Traefik and HTTPS. Use a dedicated PostgreSQL role/database and database backups. Provider setup, signing/notarization, production throttling, retention policy for receipts/conflict backups, account deletion/export and a deployment smoke test are required before opening this as a public service.
