# Brief 92: try to break the day anchor (session `day-anchor-review`, effort max)

George, 2026-11-11, 03:35, going to bed:

> after you finish reviewing Round 19 and the testing suites, please continue reviewing, improving, and hardening
> HITList until ~8am ET

and his principle for anything that holds data (COMMON): **slow is fine, wrong is not.**

Brief 82 (merged on master tonight) changed how a date with no time is stored: it was a local midnight in the zone
it was typed in, and is now 10:00 UTC on its calendar day. Every save rewrites the days it writes, a pass runs
after each iCloud import, and a pass over the whole store runs once, the first time 0.9.3 opens a store, after a
backup. That pass will rewrite real due dates on George's and his friends' devices in the morning and sync the
result to their other devices. Nobody but its author has read it. **You are the second pair of eyes, and your job
is to find what is wrong with it before it runs on real data.**

Read `dev/briefs/COMMON.md` (Round 19 block first), `dev/briefs/82-time-zones.md` (the rules and the supervisor's
design), session 82's own notes at
`/Users/gtrammell/Library/Application Support/Claude/side-session-notes/local_8995b93d-4779-400a-855f-77db7b4e0b1d/82-time-zones.md`,
then the code: core's `DayAnchor` and its tests, `HITList/Services/Dates/*`, the extension beside
`HITList/Models/Models.swift`, the date-writing lines of `TaskActions`, the Shared Tasks date lines, the JSON
snapshot, `TaskEntity`, and every test whose name starts `DayAnchor` or `TimeZone`.

## What to attack (write each as a test first; a finding without a failing test is a suspicion, say so)
1. **Reading the old form.** Brief 82 said to read an old value as the day it shows in this device's zone. The
   session instead reads it as "the day it began where it was written, which a midnight's time in UTC tells you"
   (`DayAnchor.day(of:calendar:)`). Is that always right? A midnight in UTC+13 and one in UTC−11 are the same
   instant on different days. What does it do with a value that is no zone's midnight (a half-hour or 45-minute
   zone, a date written at a DST change where midnight did not exist, a value some older build or an import wrote
   at noon, at 23:59:59, with seconds)? With a task that has `hasDueTime == false` but a time-like value? Decide
   what the safest reading is for each and whether the code does it; where it must guess, it should guess the day
   the person saw on the device that wrote it, and never rewrite when it cannot know.
2. **Idempotence and convergence.** Run every pass twice, ten times, in a different zone each time (including
   UTC−11, −12 and +14): no value may move after the first rewrite. Two devices in different zones run the
   first-run pass on the same data and sync: do they converge on the same values without writing back and forth?
   A device on 0.9.2 keeps writing the old form while a 0.9.3 device anchors after each import: is there any
   sequence where they fight, or where a day drifts?
3. **The first-run pass.** No backup, no pass: prove it (a full disk, an unwritable folder, a backup that throws
   half way). Killed in the middle: what state is the store in, and what happens at the next launch? A store with
   20,000 tasks: how long, and does it block launch or the first frame? Does it run before CloudKit has imported
   (an empty store on a new device) and then never again? Does it run in the widget's or an intent's process? On
   a side store (it must never mark George's real store)? With iCloud off?
4. **The one place.** Find every way a date reaches the store and prove each is anchored or deliberately not:
   the parser, both pickers, drag on the Mac board, postpone, repeats rolling on (every rule: daily, weekdays,
   monthly on the 31st, yearly on Feb 29), sub-tasks, the Flipboard, Review Inbox, undo of a completion, the
   Completed list's restore, import of an old export, the Claude tools, Siri, the widgets' outbox, Shared Tasks in
   both directions, the deduplicator. A date with a time must never be touched: prove it for each path too.
5. **What reads a day.** Everything that asks "is this today, overdue, this week" must give the same answer in
   every zone from Honolulu to Chatham for an anchored value: the lists, the badge, the morning summary, reminders
   for date-only tasks (when do they fire?), the widgets (the snapshot is written in one zone and can be read
   after a flight), Spotlight, the filter language (`today`, `overdue`, `7 days`, `before:`), sort orders. And at
   the two ends of the day: 00:00 to 00:01 and 23:59 local, and across a DST night.
6. **The switch.** With `DayAnchor.isEnabled` false, nothing is rewritten and everything still reads correctly,
   including values a 0.9.3 device already anchored.
7. **Catching up.** `CalendarChange`: is anything left that decides "today" once and keeps it (a cached
   formatter or calendar, a `static let`, a view's `@State now`)? The supervisor added listeners to the tab bar's
   day, Inbox, Browse, Search and the Duo's next days tonight; check those too.

## What to do with what you find
Fix what is wrong, one commit per finding, failing test first, in the files below. If a finding means the stored
form or the pass is unsafe and cannot be made safe tonight, say so at the top of your report in one sentence and
recommend switching `DayAnchor.isEnabled` off for 0.9.3: that is a perfectly good outcome. Do not weaken a test to
make it pass. Do not change the stored form.

## Ownership
Core's `DayAnchor` and the date, ordering and grouping files; `HITList/Services/Dates/*`; the extension beside
`Models.swift`; the date-writing lines of `TaskActions`, `SharedTasksRecords`, `TaskEntity`, the JSON snapshot;
tests (`DayAnchor*Tests`, `TimeZone*Tests`, new `DayAnchorReview*Tests`).
Not yours: every view (two other sessions are in them tonight: say what you found and where), Settings,
`Services/Weather/*`, companions, the share extension, the models' shape (no schema change), `scripts/`,
`dev/ROADMAP.md`, `CHANGELOG.md`, `WhatsNew.swift`.

## How to work tonight
Core's tests run in a minute (`cd HITListCore && swift test`); use them for almost everything. The Mac is shared
with eight other sessions and is slow: prefer `-only-testing` for app tests, run the three suites once at the end,
boot no simulator unless a finding needs one. Nobody answers questions or system dialogs tonight.

## Done
A table: each attack, what you tried, what happened, the test, the fix or why none was needed. Your verdict in one
sentence: is the first-run pass safe to run on George's data this morning? Test counts before and after, the
branch, changelog lines if anything a person would notice changed.
