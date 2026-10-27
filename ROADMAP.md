# HITList Roadmap

Backend and robustness work, in priority order. Written 2026-10-27, after TestFlight build 1 (0.1.0)
shipped to George's iPhone 16 and Mac. UI/UX iteration runs in parallel in separate sessions and is
not tracked here.

Guiding principle: items that get more expensive once other people's data lives in the Production
CloudKit container come first.

## Status

| # | Item | Status | Owner |
|---|------|--------|-------|
| 4 | Git baseline + one-command release script | done 2026-10-27 | Fable (this session) |
| 1 | Multi-device dedupe for seeded filters, projects, labels | in progress | Opus 5.5 session, effort High |
| 2 | Versioned schema + migration plan + schema rules | in progress | same session as 1 |
| 3 | Move the store into an App Group container | in progress | same session as 1 |
| 5 | Sync resilience (account change, reset cache, auto backup, status row) | next | Opus 5.5 session, effort High |
| 6 | Reminder robustness (reschedule on import, actions, time zones) | later | |
| 7 | App-layer tests + Xcode Cloud CI | later | Opus 5.5 session, effort High |
| 8 | Calendar (EventKit), themes, preferences | UI sessions | |
| — | External TestFlight / App Store prerequisites | before friends | George |

## 1. Multi-device dedupe

Problem: `TaskActions.seedDefaultsIfNeeded` seeds the four default saved filters when a per-device
UserDefaults flag is unset and the local store is empty. A second device launches before its first
CloudKit import finishes, sees an empty store, and seeds again. The same happens for projects and
labels created with the same name on two offline devices. CloudKit cannot enforce uniqueness.

Fix (Apple's recommended pattern):
- Seed with stable, deterministic UUIDs (UUIDv5 of a fixed namespace + name) so duplicates are
  detectable by `id`, not just by name.
- Run `Deduplicator.run(in:)` after every successful CloudKit import
  (`NSPersistentCloudKitContainer.eventChangedNotification`, type `.import`, succeeded) and once at
  launch. For each model type: group by `id`, then by case-insensitive trimmed `name`; keep the
  oldest `createdAt`; re-point `TaskItem.project` / `TaskItem.labels` to the survivor; delete the rest.
- Deterministic winner on every device so the pass converges instead of ping-ponging.

## 2. Versioned schema

Rules for the Production CloudKit container (additive only, forever):
- Never rename or delete a model or attribute. Never change an attribute's type.
- New attributes must be optional or have a default value. New relationships must be optional.
- No `@Attribute(.unique)`. No non-optional relationships.
- Every model change: bump `HITListSchemaV<n>`, add a lightweight migration stage, run the app once
  against Development, deploy the schema in the CloudKit dashboard, then release.
- `scripts/release.sh` refuses to upload while the Development schema differs from Production
  (needs a cktool management token; see the script header).

Implementation: `enum HITListSchemaV1: VersionedSchema` wrapping the current models,
`HITListMigrationPlan: SchemaMigrationPlan`, container built from the plan.

## 3. App Group store

Widgets, Shortcuts/App Intents, and a Share extension need the store in a shared container.
Moving it later means a migration for every user; today the data is throwaway.
- App Group `group.com.trammells.hitlist` on both platforms (macOS requires the team-id prefix
  form `UC8N98H3RT.com.trammells.hitlist` for the entitlement value; iOS uses `group.` form).
- `ModelConfiguration(url:)` pointing at `containerURL(forSecurityApplicationGroupIdentifier:)`
  /`HITList.store`. One-time move of an existing local store file if present.
- UserDefaults for shared settings via `UserDefaults(suiteName:)`.

## 4. Git + release script

`scripts/release.sh` bumps the build number, regenerates the project, runs the core tests, archives
and exports iOS and macOS, verifies the entitlements, uploads both with altool, commits and tags.
Run `scripts/release.sh --help`.

## 5. Sync resilience

- Observe `CKAccountChanged`; when the account changes or signs out, the system wipes the local
  mirror. Show a clear state in Settings and in the sidebar rather than an empty list.
- Settings → "Reset local cache and re-download": delete the store files, rebuild the container,
  let CloudKit re-import. Confirmation dialog, explain the data is safe in iCloud.
- Automatic JSON snapshot once a day into the app's iCloud Drive Documents folder (keep last 14).
  Manual Export/Import already exist (`SnapshotBuilder`, `SnapshotDocument`).
- Sync status row: "Synced 2 min ago", "Syncing…", "Offline", "Not signed in to iCloud",
  with the raw last error behind a disclosure.

## 6. Reminder robustness

- `NotificationScheduler.reschedule` runs only on scene activation. Also run it after each
  successful CloudKit import (the app already has the `remote-notification` background mode).
- Notification category with Complete and Snooze 1h actions.
- Reschedule on `NSSystemTimeZoneDidChange` and `significantTimeChange`.
- Respect the 64 pending-notification cap explicitly (sort by due date, truncate).

## 7. Tests + CI

- `HITListTests` target: in-memory `ModelContainer`; cover completing recurring tasks,
  reschedule, snapshot round-trip, dedupe convergence, seeding idempotence.
- Xcode Cloud workflow: test on push, archive + TestFlight on tag.

## 8. Calendar, themes, preferences

EventKit read-only overlay of today's events; theme choices within the dark palette; filter
defaults. UI sessions own these.

## External TestFlight / App Store prerequisites

Privacy policy URL (even with zero data collection), support URL, screenshots per platform,
age rating, first external build passes Beta App Review (~1 day). No code required.

## Decisions log

- 2026-10-26: iCloud private database only; home server stays a design relic (DESIGN.md).
- 2026-10-26: CloudKit.framework linked explicitly (macOS 26 sandbox bug, Apple forums 835400).
- 2026-10-26: `com.apple.developer.icloud-container-development-container-identifiers` must never be
  in the entitlements; App Store Connect rejects uploads carrying it (errors 90045 / 90285).
