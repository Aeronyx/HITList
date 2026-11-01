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
| Task popouts (no detail column; quick-add card with live chips, floating "+", inline add rows; task popout; iPhone Upcoming rows no longer drag) | done 2026-10-31; iPhone 17 simulator checked (floating "+", typed tokens → chips, Return keeps the card open, row → task sheet, … menu moves); ⌘←/⌘→ move the open task a day on Mac; Mac panel, inline add row and drag-to-day need George's eyes | Opus 5.5 session, effort High; merged and smoothed by Fable |
| Inter typeface everywhere, schema V2 (reminder offset, deadline, location, Flipboard charge fields), shared due colours | done 2026-10-31 | Fable |
| iPhone tabs + four screens (Inbox/Today/Upcoming/Browse, oval "+"; priority-then-due sort, Inbox rule, "Group" wording) | done 2026-10-31; iPhone 17 simulator checked (all four tabs, Group pushed from Browse with the "+", search finds a completed task, Today's two sections with time-only rows, Group note absent from Inbox, strip jump); real taps on the bar and Mac sidebar wording need George's eyes | Opus 5.5 session, effort High |
| Quick-add v2 (oval card, '+' options, reminder offsets, deadline, location) | done 2026-10-31; iPhone 17 simulator recorded (type "Haircut tom 11am p1 !15mb" → Tomorrow / P1 / 11:00 AM · 15 min before, location from "+", save, task popout deadline + offset change); notification at due − offset ("in 15 min · Haircut") unit-tested; Mac panel and the "+" menu tap need George's eyes | Opus 5.5 session, effort High |
| Flipboard: long-press menu, faint-green lamp, charging switches | done 2026-10-31; iPhone 17 simulator checked (recorded); Mac long-press popover and right-click menu need George's eyes | Opus 5.5 session, effort High |
| Versioned releases: CHANGELOG.md, `release.sh --version`, preflight tests (core, macOS, iOS) before any archive, version in Settings → About; quick-add title 20 pt; `Preferences` keys; 6 pt sync dot | done 2026-10-31 | Fable |
| iPhone chrome v2 (floating island bar, filter-lines view options + "…" menu with Settings, the version and the sync dot on every screen, Liquid Glass on iOS 26, confirm-before-delete dialog, week start wired through) | done 2026-11-01; iPhone 17 simulator checked (island with the list showing through, "+" above it, "…" on Today and Inbox with Settings opening from it, Inbox's Process in the "…", glass quick-add card over the dimmed list, sync dot orange when signed out); a pushed Group's Edit…, the Flipboard "…", Reduce Transparency fallback and the real phone need George's eyes | Opus 5.5 session (items 1–2), finished by Fable |
| Settings v2 (sync confirmation and check, notification test, default reminder offset, morning summary, start screen, week start, app badge, confirm delete, diagnostics, What's new) | done 2026-11-01; session checked the Settings groups and the Reminders rows in the simulator and the Check iCloud / test notification on the Mac; Fable checked Settings opening from the "…"; the test notification, morning summary and badge on the real phone need George's eyes | Opus 5.5 session, effort High; cleanup and merge by Fable |
| Motion roles, four dark themes, Liquid Glass in the design system | done 2026-10-31 on branch `motion-themes`; `hitGlass` + six `HITMotion` roles; Slate/Graphite/Midnight/Moss switch live (WCAG AA tested); glass on the sheet header, segment highlight and chip hover; crisper completion pop + slide-away. iPhone 17 simulator checked (all four themes on Today, a Group, Settings/Appearance and the Flipboard; one Slate completion; glass header vs Reduce Effects). The list views' toast/collapse curves (not this session's files) and the Mac need George's eyes | Opus 5.5 session, effort High |
| Build-6 feedback: card put-away, no inline add row on iPhone, grey empty states, uniform rows with the Group trailing, Browse/list bottom margin, Mac oval "+", Review Inbox in the "…", design-system Done buttons, Mac title field box | done 2026-11-01; iPhone 17 simulator checked (Browse scrolls clear of the island, Settings row reachable); Mac items need George's eyes | Fable |
| Mac pickers inside the window (HITCalendar, time and reminder cards) | done 2026-11-01 on branch `mac-pickers`; no `NSPopover` or system `DatePicker` left in the popouts. Mac app run with a scripted, uncommitted demo (in-memory store): all 7 quick-add cards and all 8 task-popout cards opened inside the window at the minimum 760 × 560 and at 800 × 600 (date and reminder cards below their chips in quick add; the task popout's date, reminder and deadline cards slide over their chip row at the minimum height), Escape and a click outside closed only the card, Tab moved the keyboard in (calendar arrows + Return picked "Nov 10", typing "9am" in the reminder card wrote "9am"), and the keyboard went back to the title. iPhone 17 simulator: chips still open their popovers. Looks (glass, hover, spacing) and iPad (still popovers) need George's eyes | Opus 5.5 session, effort High |
| Sync icon in every toolbar (replaces the sidebar footer and the "…" dot), Mac toolbar + as a prominent capsule, outlined confirm button in the quick-add card | done 2026-11-01; iPhone 17 simulator checked; Mac needs George's eyes | Fable |
| Build-7 feedback: sync bolt outside the pill, two controls on every screen (Jump to today, New…, Add switch), Mac "…" with Settings, one-motion card put-away, four more themes, Spotlight-proof build paths | done 2026-11-01; iPhone 17 simulator checked; Mac needs George's eyes | Fable |
| Mac Settings page (in-window, sections, shortcuts, data, previews) | done 2026-11-01 on branch `mac-settings`; no Settings window: the sidebar gear, ⌘,, the "…" Settings… and the sync bolt select `SidebarItem.settings`; seven sections (200 pt list, ≤ 620 pt content, remembered); keyboard-shortcut table, Data counts + store size, iCloud "Last change" (no sparkline: the monitor keeps no per-day counts), 56 pt swatches + live preview, Compact rows stored (TaskRow pending), About build date / Changelog / inline What's new. Mac app run with an uncommitted demo hook (in-memory store): real clicks on the gear, bolt and "…" → Settings… opened the page; all seven sections clicked and remembered at 760 × 560 and 1200 × 800; ↓ moved sections; the ⌘, item is in the app menu, but this session's window could not become key so the shortcut itself is unverified. Views checked as rendered images, every theme. iPhone 17 simulator: the sheet has the same groups; a pre-existing overflow (8 swatches in one row) fixed with rows of four. Glass pill, hover and ⌘, need George's eyes | Opus 5.5 session, effort High |
| Build-8 feedback: bolt shapes and per-theme pastel colours, Settings page takes the whole window with Back, Flipboard add tile in the grid, Inbox priority sections, Upcoming view options (Show overdue, Days shown), Mac title field without the grey box, Mac Add task row at body size, Compact rows wired | done 2026-11-01; iPhone 17 simulator checked (Inbox sections, Flipboard tile, bolt); Mac needs George's eyes | Fable |
| Build-9 feedback: slim, equal task rows and shared header spacing (`ListMetrics`, `taskSectionHeader`), no P1/P2 badge, readable Inbox priority headers, shorter "+" oval, bolt nearer the controls, Mac Settings sections in the sidebar column (no column collapse) | done 2026-11-01; iPhone 17 simulator checked (Today, Inbox, Upcoming rows and headers; Upcoming's header rows now start over the checkboxes); Mac needs George's eyes (row insets at 12 pt, header hairlines, sidebar push, small "+" control) | Fable |

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

## Task Flipboard (shipped 2026-10-28; start-red and flip sound 2026-10-31; charging and long-press menu 2026-10-31)

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
driven from the same records. Add switches with "+" (title, every N days/weeks, flips per interval)
or "Add to Flipboard" in task detail. Code: `HITList/Views/Flipboard/`, tests in
`HITListTests/FlipboardTests.swift` (`FlipboardTests` and `FlipboardRulesTests`). Not yet built from
the original idea: widgets.

**Long-press menu and the lamp (2026-10-31).** A long press anywhere on a switch, the rocker included,
opens its menu on iPhone (soft haptic as the hold registers; the rocker is no longer a `Button`, so
it no longer swallows the press); right-click opens it on the Mac and a long press there opens the
same items in a popover. Items: Flip back to red (undoes the last flip: a green switch turns red, due
on the day it was flipped since the old due date isn't stored; a charging switch loses one flip;
disabled when red with nothing counted), Edit interval…, Flips per interval…, Open task, Mark done,
Remove from Flipboard. A plain tap still flips. A green switch's LED now glows a faint green with a
soft halo (flaring once as it turns green) instead of going dark; red and the overdue breathing are
unchanged; Reduce Motion drops the breathing and the flare.

**Charging switches (2026-10-31).** `TaskItem.flipTarget` > 1 (schema V2, 1 to 10) makes a switch
need that many flips per interval: "Gym", 3 flips a week. While red each flip adds one to
`flipCount` (the first sets `flipPeriodStart`) and clicks; the flip that reaches the target charges
it, moving the due date exactly as a single flip does, with the count left at the target so the
lamps read full. When the date rule turns it red again, a `flipPeriodStart` from before the interval
being counted is stale and reads as 0 (for an overdue charger that interval is the due day moved on
by whole intervals, so last week's flips don't count this week); the next flip starts afresh. Extra
flips while charged only bounce the rocker; Mark done charges at once; lowering the target to what is
already counted charges it; editing the interval of a red charger leaves its due date alone. A
target of 1 follows the same rules and behaves exactly as before. Look: a row of lamps across the top
of the tile replaces the LED; each flip pops the next lamp on with a glow that spreads to its
neighbours; the last flip snaps the rocker green, blooms along the row and plays `bubble.caf` after
the click (both follow the Flip Sound toggle); the lamps drain right to left the first time the board
shows the next interval (remembered per device in `AppGroup.defaults`, `flipboard.shownFull`).
Captions: "2 of 3 this week" while charging, "Done this week" when charged ("today", "these 2
weeks", "this round" for other rules). The editor (now `HITSheetChrome`, with a −/+ stepper and
`HITSegmented`) has "Flips per interval" and a live preview tile whose rocker can be flipped to try
the lamps.

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
- 2026-10-31 (round 3): "Group" is the user-facing word for Project; the model and `#name`/`project:` syntax
  stay. Inbox = every dated task plus undated tasks with no Group; undated tasks in a Group show only inside
  it (notes). Today and Inbox sort priority-then-due; saved filters keep due-then-priority. Due colours:
  today green, tomorrow orange, later purple, overdue red (`HITColor.due`). Inter ships as six static 18 pt
  cuts because iOS resolves only a variable font's default instance by PostScript name.
- 2026-10-31: schema V2 deployed to CloudKit Production by George after the Development push; build 5 (0.1.0) is the first build that writes the new fields.
