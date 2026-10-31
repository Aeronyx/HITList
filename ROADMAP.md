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
| 1 | Multi-device dedupe for seeded filters, projects, labels | done 2026-10-27 | Opus 5.5 session, effort High |
| 2 | Versioned schema + migration plan + schema rules | done 2026-10-27 | same session as 1 |
| 3 | Move the store into an App Group container | done 2026-10-27 | same session as 1 |
| 5 | Sync resilience (account change, reset cache, auto backup, status row) | done 2026-10-28 | Opus 5.5 session, effort High |
| 6 | Reminder robustness (reschedule on import, actions, time zones) | done 2026-10-28 | Opus 5.5 session, effort High |
| 7 | App-layer tests + GitHub Actions CI | done 2026-10-28 | Opus 5.5 session, effort Medium |
| 8 | Calendar (EventKit), themes, preferences | UI sessions | |
| 9 | Filter language (Todoist parity, autocomplete, editor) | done 2026-10-28 | Opus 5.5 session, effort High |
| — | External TestFlight / App Store prerequisites | before friends | George |

### UI

| Item | Status | Owner |
|------|--------|-------|
| Completion delight (sound, strike-through, slide-away, undo toast) | done 2026-10-28 | Opus 5.5 session, effort High |
| Completion sounds (five built-ins + custom file) | done 2026-10-28, awaiting George's ears | Opus 5.5 session, effort Medium |
| Upcoming view (week strip, day sections, drag to reschedule) | done 2026-10-28; iPhone drag conflicts with the row context menu (verified 2026-10-31), fix in the popouts brief; Mac drag unverified | Opus 5.5 session, effort High |
| Inbox polish (empty state, count, Process mode) | done 2026-10-31 | Opus 5.5 session, effort High |
| Task Flipboard | done 2026-10-28 | Opus 5.5 session, effort High |
| Design system (custom buttons, toggle, chips, fields, sheet chrome; editors, Settings, sidebar "+", "…" menu) | done 2026-10-31; guide in HITList/Support/DesignSystem/README.md | Opus 5.5 session, effort High |
| Task popouts (no detail column; quick-add card with live chips, floating "+", inline add rows; task popout; iPhone Upcoming rows no longer drag) | done 2026-10-31; Mac panel and Mac drag-to-day need George's eyes | Opus 5.5 session, effort High |

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

## Task Flipboard (shipped 2026-10-28; start-red and flip sound 2026-10-31)

A Flipboard screen (sidebar, under Upcoming) shows recurring chores as a wall of skeuomorphic
rocker switches: green while the task is due in the future, red once it is due or overdue (the LED
glows, and pulses slowly when overdue unless Reduce Motion is on), with a thin light bar and
"2 of 3 days" for time elapsed in the interval. Red sorts first, most overdue on top. Tapping a red
switch flips it with a sprung 3D rocker animation, a haptic and a light-switch click (`flip.caf`,
110 ms, synthesised; "Flip Sound" toggle in the board's … menu, on by default, silent switch respected)
and completes the task
through `TaskActions.toggleCompletion`; like a physical switch, the flip then restarts the interval
from the flip day (George's decision, 2026-10-28), so a 3-day switch flipped on Thursday is due
Sunday. A new switch starts red with "Flip to start" and an empty light bar (it is due the day it is
created; George's call, 2026-10-31): "Shave" every 2 weeks is red, a flip makes it green for 14 days,
then it is red until flipped again. "Add to Flipboard" makes a task without a future due date due
today (red); one due in the future keeps that day (green). A green switch asks before being done early. A switch is just a recurring task without a time that carries the
`flipboard` label (stable seeded id), so there is no schema change and a real board could later be
driven from the same records. Add switches with "+" (title, every N days/weeks) or "Add to
Flipboard" in task detail; long-press or right-click edits the interval, opens the task, or removes
it. Code: `HITList/Views/Flipboard/`, tests in `HITListTests/FlipboardTests.swift`. Not yet built
from the original idea: widgets and chargeable tasks on the board.

## External TestFlight / App Store prerequisites

Privacy policy URL (even with zero data collection), support URL, screenshots per platform,
age rating, first external build passes Beta App Review (~1 day). No code required.

## Ideas backlog (George, 2026-10-28)

Not scheduled. Each becomes a roadmap item when picked up.

- **Completion delight.** Todoist's completion sound, strike-through and the row sliding away. A
  short custom sound (respecting silent mode), haptic on iOS, 250 ms strike + collapse animation,
  undo toast for 5 s.
- **Chargeable tasks** ("gym 3x week"). A quota per period rather than a due date: `n` ticks per
  week/month, shown as a persistent card between Today and Overdue with a progress ring until the
  quota is met, then it rests until the period rolls over. Schema: new optional fields on
  `TaskItem` (`quotaCount`, `quotaPeriod`, `quotaTicks: [Date]`), so a V2 schema version.
- **AI / API / MCP.** First-class Claude integration: an MCP server exposing tasks, filters and
  quick-add (so Claude Desktop / Claude Code can read and add tasks), App Intents for Siri and
  Shortcuts, and a documented JSON export. Possibly a local HTTP endpoint on the Mac for automation.
- **Fun.** Nyan Cat very rarely flying across the top of the window; seasonal pixel-art variants of
  a few buttons on the solstices, Halloween and similar; all behind a "Delight" toggle in Settings.

## Decisions log

- 2026-10-26: iCloud private database only; home server stays a design relic (DESIGN.md).
- 2026-10-26: CloudKit.framework linked explicitly (macOS 26 sandbox bug, Apple forums 835400).
- 2026-10-26: `com.apple.developer.icloud-container-development-container-identifiers` must never be
  in the entitlements; App Store Connect rejects uploads carrying it (errors 90045 / 90285).
- 2026-10-28: Filter language skips Todoist's collaboration terms (`assigned`, `added by`, `shared`,
  `workspace`), `subtask`, `/sections` and `deadline:`: HITList is single-user and has no sub-tasks,
  sections or deadlines, so they get explanatory errors instead. `,` stays an AND (one list per view)
  rather than Todoist's "separate lists".
