# macOS distribution

`macOS releases` is separate from container deployment. It builds one universal
Intel/Apple Silicon `Timeit.app`, signs it with Developer ID and the hardened
runtime, notarizes and staples both the app and its drag-to-Applications DMG,
then publishes the ZIP, DMG, matching dSYMs, checksums and notarization receipts
on GitHub Releases. A single signed Sparkle feed is published last.

## Credentials

The GitHub environment `PROD` needs:

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `APPLE_CERTIFICATE_P12_BASE64` | Base64 PKCS#12 certificate and private key |
| Secret | `APPLE_CERTIFICATE_PASSWORD` | PKCS#12 export password |
| Secret | `APPLE_API_PRIVATE_KEY` | Apple notarization API `.p8` key |
| Secret | `SPARKLE_PRIVATE_KEY` | Timeit's exported Sparkle signing seed |
| Variable | `APPLE_TEAM_ID` | Developer ID team |
| Variable | `APPLE_API_KEY_ID` | Notarization key identifier |
| Variable | `APPLE_API_ISSUER_ID` | Notarization issuer |
| Variable | `SPARKLE_PUBLIC_ED_KEY` | Timeit's public Sparkle key |

Feed publication uses the existing `ML_DEPLOY_*` secrets, including the existing
`github-deploy` SSH identity. No new SSH credential or source checkout is needed
on the VPS. The signing keychain is temporary and credentials are removed even
when a job fails. Keep a private backup of the Sparkle key: installed apps trust
this key, so losing it prevents ordinary signed updates.

## Publish

The version in `apps/macos/Info.plist` must match stable/beta tags. Create an
annotated tag with release notes on a tested commit reachable from `main`:

```sh
git tag -a v0.1.0-beta.1 -m 'First signed beta of Timeit'
git push origin refs/tags/v0.1.0-beta.1
```

Stable uses `v0.1.0`. To publish a nightly from `main`:

```sh
gh workflow run distribution.yml --repo mathis-lambert/timeit --ref main
```

The workflow creates `nightly-<full commit SHA>`. Nightlies are explicitly
requested; ordinary pushes to `main` only run CI/container deployment. The
workflow can also be dispatched with `-f tag=<existing tag>`.

All channels use the same workflow `run_number` for `CFBundleVersion`. Never
replace this workflow with a new workflow whose counter starts again without
first arranging a higher build baseline. The marketing version remains numeric.
The release manifest records the tag, channel, build and source revision.

Stable has no Sparkle channel attribute, Beta uses `beta`, Nightly uses `nightly`.
The app identity and data directory never change. Channel subscriptions persist;
returning to Stable waits for a higher stable build and never downgrades.

## Publication and recovery

A release stays in draft until every artifact has uploaded. Published artifacts
are never overwritten by the workflow. If a build fails with an incomplete draft,
inspect its failure and explicitly remove that draft before retrying. Retrying a
published release only regenerates/publishes its feed from the existing ZIP.

The feed generator verifies the existing signed feed before preserving every
release in it. The server performs a locked atomic replacement of the exact
signed bytes, refusing lost entries, altered archive signatures or reused build
numbers. A delayed older release cannot displace a newer release. Clients verify
both the feed signature and the archive signature.

The VPS adds only `publish-appcast.py`, `.appcast.lock` and
`updates/appcast.xml` to the existing runtime directory. Downloads stay on GitHub.
The website root remains reserved for the future presentation site.

## Acceptance

Automated checks cover app/core tests, universal architectures, nested signatures,
matching dSYM UUIDs, Apple's notarization acceptance, stapled tickets, Gatekeeper
assessment, signed feed verification, monotonic publication and public feed bytes.

Before declaring the updater fully validated, install a downloaded signed build
on a disposable macOS account, then update to a second signed build through
Sparkle. Check relaunch, channel persistence and unchanged projects/running timer.
Repeat Beta → Stable and confirm there is no downgrade. Do not use the real
workspace for release smoke tests; the current `--demo` startup still opens its
normal database before entering demo mode.
