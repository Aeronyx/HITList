# Brief 72: Switchboards and routine switches (session `switchboards`, effort xhigh)

George, 2026-11-10, on 0.9.0 (20), for a friend who uses the Flipboard for routines:

> Also, my friend wants to use the Flipboard slightly differently for his own use case; it's still essentially the same
> functionality, it just needs a better daily switch system (e.g. "reset every day at 4am") and groups of switches
> called Switchboards so he can form daily/weekly routines with groups of switches. Essentially, switches should be
> more focused around routines instead of tasks and allow times to be attached. By default, switches should not become
> tasks when overdue unless the user toggles that option on. Different Switchboards can function as groups such as
> "Deep Clean" or "Before Bed" that contain tasks a user might do daily before bed or weekly to clean the house. Of
> course, none of these routine switches should become actual tasks unless the user toggles on "overdue becomes task".
> Then, looking at your Flipboard in the app becomes more like a personal status check without the stress of your real
> todolist, which is exactly the point.

Read `dev/briefs/COMMON.md` (Round 16 block first), `dev/briefs/ROUND-16.md`, `59-flipboard-intervals.md` and
`69-flipboard-add.md`, the header of `HITList/Models/SchemaVersions.swift` (every rule in it binds you),
`HITListCore/Sources/HITListCore/FlipboardSwitch.swift` and `HITList/Views/Flipboard/FlipboardRules.swift`.

Today a switch is an open recurring task with no time of day and the `flipboard` label. Its due date is "next due":
green while that day is after today, red from that day on; a flip rolls the due date on by the rule, counted from the
flip day. A red switch is listed in Today and the Inbox as today's task (round 13). That stays the machinery: a switch
is still a `TaskItem` with the label, its state is still its due date, and older builds on a friend's other device
must still read every switch as a switch or as an ordinary repeating task, never crash or lose it.

## The rules (George's words above; where he left a choice open the supervisor chose, marked "choice")
1. **A switch is never a task by default.** Green or red, it is on the Flipboard only: not in Today, the Inbox,
   Upcoming, search, filters, the badge, the morning summary, the sidebar counts, Siri's lists or Claude's. This
   replaces round 13's rule and applies to every existing switch from the first launch.
2. **"Overdue becomes task"** is a toggle, off by default, on a switch and on a Switchboard (choice: both; a switch is
   opted in when its own toggle or its Switchboard's is on). An opted-in switch is listed exactly as round 13 listed
   every red switch (as today's task, never as overdue, once, completing its row flips it), from the moment it is
   due: a switch without a time is due from the start of its day; a switch with a time is due from that time.
   A query that names `@flipboard` still sees every switch (`FilterQuery.namesFlipboard`).
3. **A switch may have a time** ("Take meds 21:00"). Choice: the time is when the step is due. It shows on the
   switch, orders the switches of a board (timed ones by time, then the untimed), decides when rule 2 applies, and
   reminds at that time exactly as any timed task does (the existing reminder settings and offsets apply; no time,
   no notification). Before its time a red switch is calm ("21:00"); after it, it reads as late in the Flipboard's
   own quiet way. The membership rule loses `!hasDueTime`. Type it in the switch card's name ("Take meds 9pm" fills
   the time, as the interval phrases fill the dial) or set it with the card's time control (reuse the editor's time
   picker card; no default SwiftUI `DatePicker` look).
4. **Switchboards** are named groups of switches: "Before Bed", "Deep Clean". A new model, `Switchboard`:
   a name, an order, a cadence (Daily or Weekly), a reset time (choice: 04:00 for a new board, shown plainly on its
   card and header: "Daily · resets 04:00"), for a weekly board the weekday it resets on (default: the week start
   from Settings), and "Overdue becomes task". A switch belongs to at most one Switchboard (choice: an optional
   relationship; a switch with none is a loose switch on the main board, exactly as today, and existing switches
   stay loose: nothing is migrated and no default board is created, so two devices cannot make two of them).
5. **A board's day starts at its reset time.** With a 04:00 reset, 01:30 on Tuesday is still Monday's board day:
   switches flipped on Monday evening stay green until 04:00, then every switch of a daily board turns red again
   together. A weekly board's week runs from its reset weekday at the reset time to the next. Switches in a board
   follow the board's cadence (the card shows "Daily, with Before Bed" in place of the interval dial); a flip lands
   the due date on the board's next period, not on "interval from the flip day". Chargers (`flipTarget` > 1) count
   within the board's period. Loose switches keep every rule they have today, midnight included.
   Watch the dates: an untimed switch's due date is a calendar day standing for a board day; a timed one's is a real
   moment, and 00:30 belongs to the board day that began the evening before. Put this arithmetic in core, pure, with
   tests around midnight, the reset time, daylight-saving changes and a weekly reset day; the views only ask it.
6. **The Flipboard is a calm status check.** Loose switches first, looking exactly as today when there are no
   Switchboards. Then each Switchboard as a section in its order: its name in the list section header style, the
   cadence line, how many are done ("3 of 5"), a "+" 6 pt after the name that adds a switch to that board (the
   pattern of "Groups +"). Every switch tile on the screen stays one size. No overdue alarm colours beyond what a
   red switch has today, no counts of what is late.

## Items (one commit each, failing test first where there is logic)
1. **Schema V6**, additive only. `Switchboard` (CloudKit record type `CD_Switchboard`): `id`, `name`, `sortOrder`,
   `cadence` (a string raw value, so a later cadence is not a retype), `resetMinutes` (minutes after midnight),
   `resetWeekday` (0 = the week start, else Calendar's 1...7), `overdueBecomesTask`, `createdAt`, `updatedAt`, and
   `switches` (to-many, nullify). `TaskItem` gains `switchboard` (optional to-one) and `overdueBecomesTask`
   (Bool, default false). Nothing else, and no field "for later". Freeze V5 (`SchemaV5Models.swift`), pin V5's hashes
   while it is still live, add the lightweight stage, add `testV6OnlyAdds…`, put a sample Switchboard with a switch
   in it into `-seedSampleData` (`CloudKitSchemaTests.testSampleDataCarriesEveryOptionalField` must pass), carry the
   new model and fields through the snapshot and backup JSON (`Snapshot`, `SnapshotBuilder`, `LocalBackup`; round
   trip tests; a backup from 0.9.0 (20) still restores), `Deduplicator` if it needs to know the field, Spotlight and
   the Claude export if they list switches. Run every Debug app with `-disableCloudKit YES`: the schema push to
   CloudKit Development is the supervisor's, after the merge.
2. **Core rules**: `FlipboardSwitch` membership, sides, "due now", listing under rules 1, 2, 3 and 5;
   `FilterableTask` gains what it needs with defaults that keep every other conformer as it is; `TaskOrdering`,
   `GroupedOrdering`, `UpcomingSchedule`, `NotificationPlan`'s `isSwitch` counting and the morning summary follow.
   Existing tests that pin round 13's "red is in Today" change to the new default and gain the opted-in case.
3. **App rules**: `Flipboard` (`FlipboardRules.swift`) for board days, flips, flip back, chargers, captions with a
   time, creating a switch in a board, moving a switch between boards and out, deleting a Switchboard (ask: delete
   its switches too, or keep them as loose switches; deleting syncs to every device, never use a delete as a reset).
4. **The switch card** (`SwitchCard`, `SwitchDraft`, `SwitchControls`): time, "Overdue becomes task", which
   Switchboard (None or one of them); still a small card, never a sheet, on iPhone and the Mac.
5. **The Switchboard card**: name, Daily or Weekly (`HITSegmented`), reset time, reset day when weekly, "Overdue
   becomes task", Delete Switchboard…; a small card like the switch card. "New Switchboard…" lives in the
   Flipboard's existing menu (the "…" on the Mac and iPad, the view options on iPhone); a board's name opens its
   card (and a long-press or right-click menu: Edit…, Delete…). Reorder boards from that menu or by drag if cheap.
6. **The board's sections** (rule 6) in `FlipboardView`/`FlipboardGrid` on iPhone, the Duo, iPad and the Mac, and
   the tile's time line in `FlipSwitchTile`.
7. **Demo data and a tip.** `-seedDemoData` gets "Before Bed" (daily, 04:00, four switches, one with a time, two
   flipped) and "Deep Clean" (weekly, three switches), so the screenshots show them. One TipKit tip on the Flipboard
   for people who had red switches in Today: switches stay on the Flipboard now; "Overdue becomes task" on a switch
   brings it back to Today when it's due (`HITTips.swift`: your one tip only).

## Ownership
`HITList/Models/Models.swift`, `SchemaVersions.swift`, new `SchemaV5Models.swift`, `HITListTests/SchemaTests.swift`,
`CloudKitSchemaTests.swift`; `HITList/Views/Flipboard/*`; core `FlipboardSwitch.swift`, `FilterableTask.swift`,
`TaskOrdering.swift`, `GroupedOrdering.swift`, `ListRow.swift`, `FilterQuery.swift` (the switch lines only),
`Snapshot.swift`, a new core file for board days; `HITList/Views/Upcoming/UpcomingSchedule.swift` (switch lines),
`HITList/Services/TaskActions.swift` (seeding, switch creation and roll-over), `SnapshotBuilder.swift`,
`LocalBackup.swift`, `Deduplicator.swift`, `Services/Notifications/NotificationPlan.swift` and `MorningSummary.swift`
(switch lines), `NotificationScheduler.swift` (the item it builds), `Services/Spotlight/SpotlightSync.swift`,
`Services/Claude/ClaudeExport.swift` and `ClaudeToolHandler.swift` (switch lines), `Services/Intents/*` (switch lines),
`HITList/Views/Tips/HITTips.swift` (one tip), `SidebarCounts` at the foot of `SidebarView.swift` only if the counts
need a line (the rest of that file is brief 70's), their tests (`FlipboardTests`, `FlipboardAddTests`,
`FlipboardLightsTests`, `ListRulesTests`, `NotificationPlanTests`, `SnapshotRoundTripTests`, `SeedingTests`, new
`SwitchboardTests`), the two Flipboard tests inside `HITListUITests/HITListUITests.swift` (edit them in place) and a
new `HITListUITests/SwitchboardUITests.swift` for yours, your `dev/ROADMAP.md` row.
Not yours: `RecurrenceRule`, the quick-add parser and `DateExpression` (71: call them as they are; the switch card
reads a typed time through the parser's existing time phrases); `SidebarView`'s rows, `ContentView`, `ScreenMenu`,
`ListChrome`, `QuickAddEntry` (70); `BrowseView`, `Views/Groups/*`, the bolt (73); `TaskRow`, `TaskListView`,
`InboxView` (the lists read your core rules; if one needs a line, say which in the report and the supervisor adds
it); `HITTokens`; `CHANGELOG.md`, `WhatsNew.swift`, `scripts/`.

## Done
Screenshots on the iPhone 17 simulator and the Mac (demo data): the Flipboard with loose switches and both
Switchboards, before and after the reset time (inject the clock, or a Debug `-flipboardNow` argument); the switch
card with a time and the toggle; the Switchboard card; Today without switches, and with one opted-in switch after its
time. A table in the report: every place a switch could appear as a task, and what it does now by default and opted
in. What an older build (0.9.0 (20)) shows for a board switch and for a timed switch that synced to it. The exact
CloudKit record type and field names the schema push will add (for George's deploy). All three suites green.
