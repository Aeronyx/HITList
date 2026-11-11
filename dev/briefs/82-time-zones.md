# Brief 82: a day is a day everywhere (session `time-zones`, effort xhigh)

George, 2026-11-11, on 0.9.2:

> WeatherKit has been enabled in App Services. The app should ask for the user's approximate location on first load
> in, and Weather should be on by default (if the user accepts). It should say it does this to automatically adjust
> to different timezones (and use weather effects), which should also be true of this app, and then we can use that
> for weather effects/weather-related animations for each creature while they're awake.

Your part of that sentence is "automatically adjust to different timezones … should also be true of this app".
Brief 83 asks for the location and feeds the weather; you make HITList right when the time zone changes: a flight,
a second device in another zone, a shared list with a friend abroad. No permission is needed for any of it: the
device knows its zone.

Read `dev/briefs/COMMON.md` (Round 19 block first), `dev/briefs/ROUND-19.md`, then the date code: core's
`DateExpression`, `RecurrenceRule`, the ordering and grouping files, the widget snapshot rules; the app's
`Models.swift` (`dueDate`, `hasDueTime`, `deadline`, `reminderDate`, `flipPeriodStart`), `TaskActions`,
`NotificationScheduler` (its `triggers` already include the zone and the day), `Services/Calendar/CalendarEvents`
(it listens too), the Flipboard's period rules and the Shared Tasks store.

## What the supervisor found (confirm or correct it first)
A due date is a `Date` plus `hasDueTime`. Core takes `calendar: Calendar = .current` in 61 places and the app says
`Calendar.current` in 36; only reminders and calendar events react to `NSSystemTimeZoneDidChange`. If a date-only
due date is stored as midnight in the zone it was typed in (the supervisor believes so, and did not check), then:
- fly west and every date-only task shows a day early (midnight in Chicago is 22:00 the day before in Los Angeles);
- a Mac at home and an iPhone abroad disagree about which day a task is due;
- a shared task dated by a friend in Tokyo shows the wrong day in Chicago.
Timed tasks are instants and read correctly anywhere, shifted to the local hour.

## The rules
1. **A day is a day.** A date with no time (a due date without `hasDueTime`, a deadline, anything else your audit
   finds) names a calendar day, and it is that same calendar day on every device, in every zone, before and after a
   zone change. "Due Thursday" never becomes Wednesday because someone flew.
2. **A time is a moment.** A timed one-off task keeps its instant, as Calendar and Reminders do: 09:00 written in
   Chicago is 07:00 in Los Angeles. Repeating tasks and switches store a time of day, so their next occurrence is
   at that hour where the person is. Pin both with tests and say so in the report; do not change either.
3. **Everything catches up by itself.** When the zone or the day changes while the app is open, in the background
   or closed, nothing needs a relaunch: Today, Overdue and Upcoming regroup, the Mac board is on today, the badge,
   the widget snapshot, the Switchboards' resets, the morning summary, reminders (already), calendar events
   (already). One shared source of "the calendar changed" (zone, clock, day, significant time change) that all of
   them listen to; `NotificationScheduler.triggers` has the list today.
4. **No schema change, and older builds keep reading the right day.** George's and the friends' devices update at
   different moments.
5. **Slow is fine, wrong is not** (COMMON): never move a task to another day on the device it was written on.

## The stored form (the supervisor's design; if your audit shows it cannot work, stop this item and report, do
## not invent another stored form)
- A date-only value is stored as **10:00:00 UTC on its calendar day** (the day's anchor). That instant falls
  inside the same calendar day in every zone from UTC−10 (Honolulu) to UTC+13:45 (Chatham in summer), so every
  comparison against local day boundaries, every formatter and every older build reads the right day with no
  change. In UTC−11, −12 and +14 it reads a day off: say so in the report, and fix it only if your audit shows a
  small, complete way (a core helper every reader already passes through).
- One pure function in core (`DayAnchor` or the name you prefer) turns any instant plus a calendar into its day's
  anchor, and says whether a value already is one. **Idempotent**: a value already at 10:00:00 UTC is left alone
  whatever zone the device is in (otherwise a device in a far zone would walk a date forward a day per save).
- A value in the old form (anything else) is read as the calendar day it shows **in this device's zone now** and
  rewritten to that day's anchor.
- Writers keep producing what they produce today (local midnights from the parser, the pickers, the repeats, the
  board's drag, import, Siri, the Claude tools, Shared Tasks); the anchoring happens in **one place** at the model's
  edge (find the narrowest: a pass over changed tasks when the context saves, or the one setter everything already
  uses), plus a pass after each CloudKit import (an older build elsewhere keeps writing the old form) and one pass
  over the whole store the first time this build runs. Each pass logs how many values it rewrote (unified log,
  category `dates`, and one line in the sync log).
- **Before the first whole-store pass rewrites anything, a backup exists**: call what `LocalBackup` already does
  for the daily copy and wait for it. No backup, no pass (try again next launch).
- **One switch** (`DayAnchor.isEnabled` or similar, a single constant read in one place) turns all rewriting off
  and leaves reading untouched, so the supervisor or George can hold it back without a revert.
- Ordering: anything that puts date-only tasks before timed ones, or sorts within a day, by comparing instants
  must give the same order as today. Find them (`Ordering`, `GroupedOrdering`, the Upcoming board, the widgets'
  rules) and pin the order with tests before you change a value's hour.
- "Overdue": a date-only task is overdue from the day after, never from 10:00 UTC on its day. Pin it.
- The same rule for the export and import JSON (an older export imports in the old form and is anchored), the
  widget snapshot, Spotlight, the Claude connector's dates, Siri's intents and the Shared Tasks store.
- The Flipboard: a switch flipped today is still flipped after the zone changes; a Switchboard resets at its hour
  where the person is, once, never twice in a day and never skipping more than the travel itself skips. Tests.

## Items (one commit each, failing test first)
1. **The audit**, as tests that fail today: a store written in one zone and read in another (core with injected
   calendars for Honolulu, Los Angeles, Chicago, UTC, London, Kolkata, Tokyo, Auckland in summer, Chatham; the app
   with an in-memory container), for each date field. Write down, in the report, how each field is stored now.
2. **The anchor** in core and its tests (every zone above, both directions, idempotence, DST nights).
3. **The one place, the import pass, the first-run pass**, the backup before it, the switch, the logging.
4. **Catching up**: the shared "calendar changed" source and everything in rule 3 that did not listen.
5. **The edges**: JSON, snapshot, Spotlight, Claude, Siri, Shared Tasks, the Flipboard.
6. **Seen working**: the same side store (`-seedDemoData YES`, sync off) opened under two zones, on the Mac
   (`open -n --env TZ=Pacific/Honolulu …`, then `--env TZ=Asia/Tokyo`) and in your simulator
   (`SIMCTL_CHILD_TZ=…`): Today and Upcoming show the same tasks on the same days, in screenshots side by side.
   Then a zone change while the app is open, as far as you can produce one, and what you could not.

## Ownership
Core's date, ordering and grouping files and a new anchor file; an extension file of your own beside
`HITList/Models/Models.swift` (no change to any model's shape: `SchemaTests` must stay green untouched),
`TaskActions` (only where a date is written), a new `HITList/Services/Dates/*`, `NotificationScheduler` (its
trigger list, moved to the shared source), the trigger lines of `Services/Widgets/WidgetSnapshotWriter`,
`Services/Calendar/CalendarEvents` and the badge, one start-up line in `HITList/HITListApp.swift`, the lines in
`TaskListView`, `Views/Upcoming/*` and `Views/Flipboard/*` that decide what "today" is (to listen, nothing else),
the Shared Tasks store's date lines, the JSON snapshot's date lines, new tests (`DayAnchor*Tests`,
`TimeZone*Tests`).
Not yours: every Settings view (86), `Services/Weather/*` and `project.yml` (83), `Support/Companions/*` and
`Views/Companions/*` (84, 85: the companions' night follows their own clock, not yours), the models' shape,
`dev/ROADMAP.md`, `CHANGELOG.md`, `WhatsNew.swift`, `scripts/`.

## Done
The table of every date field: how it was stored, how it is stored now, what a zone change does to it, the test
that pins it. The two-zone screenshots. What the first-run pass rewrote on the demo store (the log lines). What is
still wrong in the three far zones, in one plain sentence. What George should try on a real trip, or by changing
his iPhone's zone in Settings → General → Date & Time, in words he can follow. All three suites green.
