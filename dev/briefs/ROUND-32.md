# Round 32: the engine made ready for George's own devices, and a review of the whole app (2026-11-16, night)

0.9.13 was released on 2026-11-16 (build 30). George's message that night, verbatim:

> Thanks, I ran the xcrun command.
> Yes, we don't need encryption right now; this is not something I plan to put on the App Store, only to share with
> friends.
> Remember to always tell me if any of my friend's data is gonna be wiped if ever so they can export it beforehand.
> Please work freely and complete the sync engine.
> The app is largely feature complete, or as far as I wanted it to get for an initial release; let's shift into
> review and hardening mode so we can prepare for a real launch, but I also won't feel comfortable launching until
> we have at least a few days of experience with the new sync system to confirm its legitimacy, so we have some
> time. Don't be afraid to make feature changes as well if you notice/think of glaring issues or objective upgrades
> during your review, just be sure to make me aware of them somewhere in your concise output. Please proceed with
> focused review however you see fit (using Opus 5.5 subagents as often as possible), and continue using my
> connected iPhone for development as needed.

The Fable 5.2 supervisor, with fourteen Opus 5.5 agents started with the Agent tool (briefs 147 to 160; no
sessions): six reviewers and two code agents first, then five agents fixing what the reviews found. The supervisor
built the switch, the move's screen, the audit and the rehearsal himself, and ran the rehearsal on George's iPhone
beside this Mac. Every report is in the notes folder, `round-32/<brief>/REPORT.md` (the harness refused the agents'
own files; the supervisor saved each).

## What the rehearsal found that nothing else had

**Apple's `CKSyncEngine`, left to schedule itself, does not catch up after a relaunch.** Three reviews, a
simulation of 8,000 histories and the transport's 18-step probe had passed. Then, with the phone as a true second
device: the phone edited while the Mac's app was closed; the Mac reopened; its fetch "ended" and brought nothing;
the bolt filled; Check iCloud… on the engine (built that evening) said six records differed. CloudKit asked
directly, beside the engine, named the zone as changed. A trace of every engine event showed the fetch beginning
and ending with nothing between. With `automaticallySync` off the same relaunch fetched 73 changed records and the
comparison was exact. The probe had never seen it because the probe runs the engine in manual mode: the mode that
was proven was not the mode that shipped. Now it is (`dev/SYNC-ENGINE.md` section 6a): the app asks for each sync
itself (launch, coming forward, a push, and a pump after a change with retries of its own), and keeps a push
subscription of its own.

What misled for an hour: two stores on one Mac showed the same symptom for another reason (iCloud's change feed
does not come back to the device a change was made on), so it looked like the known "one device" limit until the
phone showed it too.

## The engine

- **A released build may run it, for a store that was moved** (`SyncEngineSwitch`). The group that moves a store
  is in Settings → iCloud, hidden until the environment row is tapped seven times; always shown on a store that
  is on the engine. A move waiting for a reopen can be taken back. Moving to the engine warns while the mirror's
  bolt is not filled.
- **The way back asks which device this is**: the first sends, every other downloads a fresh copy. Rehearsed both
  ways; a second device that came back with its own file doubled the items made meanwhile.
- **Check iCloud… on the engine** (`SyncEngineAudit`): a sync, then every record read afresh by a second road and
  compared field by field. Repairs nothing.
- **Its schema is a file**, `dev/cloudkit/sync-engine.ckdb`, pinned to `SyncSchema`; `release.sh` checks
  Production against it and prints the three steps. The engine's container's Development side was reset
  (`cktool reset-schema`: the supervisor's own test records) and the file imported, so what George deploys is
  exactly the file. The probe must not run again before he has.
- **149** (merged): a fetched record that cannot be read stays owed; an expired change token is answered; the
  ledger's file is moved aside only when damaged.
- **150** (merged): the simulation's standing failures, each fixed or pinned as a written limit; 1,000 histories of
  300 steps of every fault set with no failure. Two limits written into section 5.
- **148's findings**: a reset replaces the engine before the forgotten state is written (the supervisor); the rest
  with 160.
- The transport's lines are in the person's sync log now, with one line per fetch (what it brought, whether it
  reached the zone), so a week on the engine can be read afterwards.

## The rehearsal, run by run (CloudKit Development; logs in `build.noindex/round-32/reh/`)

1. **Two stores on this Mac, mirror to engine**: both on the mirror with the demo week (30 items); the first moved
   and sent 31 records; the second found all 30 as it held them and sent nothing; edits and a deletion went
   through; Check iCloud… exact.
2. **The way back on those two stores**: the first, reopened on the mirror, sent everything that changed meanwhile
   (the mirror's audit agreed on the second launch); the second, coming back with its own file, ended with 21
   tasks where 19 were right. Hence the two choices.
3. **George's real tasks** (`-seedFromNewestBackup`: each device's newest daily backup into a side store, ids
   kept): the Mac sent 68 records; the phone's copy (a day older) met them as M3 and M5; 67 items identical on
   both and in iCloud.
4. **The fault and its fix**, above.
5. **In its final shape, two devices**: the Mac caught up at launch with the phone's edits; the phone's own edits
   went a second after they were made; a change on the Mac reached the phone on a push in seconds. The phone's
   did not reach the Mac that night (no push reached this Mac's push daemon; in round 31 it did).
6. **The whole road with two devices**: a new store on each device on the mirror, importing the same 30 items (two
   of them doubled by `id`, left by run 2); the Mac moved, merged the doubles and sent 31; the phone moved, merged
   them the same way and found all 30 already there; edits on both crossed; then the way back, the Mac sending
   (audit agreed, 19 tasks), the phone downloading (agreed, 19 tasks).

What George's phone carried: a Debug build from about 22:07 (it replaced the TestFlight build; his real store,
settings, Spotlight, reminders and backups are out of a Debug build's reach by code); side stores
`HITList-r32real` and `HITList-r32pm` in the app's group container. He reinstalls from TestFlight.

Noticed on the way: the newest daily backup of the real store is from 13 November on the phone and 14 November on
the Mac (`-rehearsalListBackups`: file names and the store's own note of its last backup). Nothing in the backup's
code changed since. Either the real apps were not brought forward since, or backups fail silently (151's finding;
156 makes a failure visible). George was asked to look.

## The reviews (each report in the notes folder)

| Brief | What | Findings that mattered |
|---|---|---|
| 147 | The engine on the real store in a released build | The way back doubles items on a second device; a seed dated 2001 wins the name merge; the name merge strands a task; a move on the phone stopped the engine; the account switch has two owners |
| 148 | The transport against Apple's documentation | A Production schema not deployed refuses every record for good; a deletion's note forgotten while its save commits; a reset lets the old engine write its state back |
| 151 | Everything outside sync that can lose data | A label deleted by one swipe (Flipboard's own too); the merge by name deletes what was made on purpose; a Todoist import drops a same-titled task; notes have no limit; undo of a repeating completion loses its reminder and ticks |
| 152 | What can crash or hang | Spotlight reads models after awaiting; delayed deletes carry the model; editors save into a model a merge deleted |
| 153 | Every screen through a new person's eyes | A reminder never fires until Settings → Reminders is found; nothing says what the bolt means; the empty Flipboard says nothing; developer words on the iCloud page |
| 154 | The lists at 5,000 tasks, measured | A check-off 5.2 s of CPU, a list switch 2 to 3 s, a list at rest running every minute |
| 155 | What leaves the device and what can get in | Titles in the sync log; a private task shown to Claude when nested; the privacy manifest lacks two categories; a ZIP that exhausts memory. And: the repository is public |

## The fixes

- **156** (merged): a label on tasks asks before it goes and Flipboard's own is never offered Delete; the editors
  refuse a used name and save by id; no merge by name on the engine, and filters merge by name only when their
  queries are equal; a Todoist import keeps a second task of the same title, and a stopped one says what it wrote
  and can be undone; Import JSON asks before bringing back what is not here; the ZIP's limits; the daily backup
  runs off the main thread and says when it failed.
- **157** (merged): the task card acts by id after its delay; a full undo for a repeating task (reminder and ticks
  back); the move to Shared Tasks asks when something would be dropped; typing is kept when the app goes to the
  background; Spotlight reads before it awaits; Siri and Shortcuts refuse in plain words on the in-memory
  fallback; "All tasks but @private" hides a sub-task that carries the label itself.
- **159** (merged): no titles, Group names or the Mac's user name in the logs; Claude's `update_task` and
  `complete_task` say they change what is there, and a description with text is erased only on
  `clear_description`; the privacy manifest's two categories; true words for the location question.
- **The supervisor**: notifications are asked for at the first task with a reminder (they were silently off); the
  empty Flipboard says what a switch is; the iCloud page says what the bolt means and drops the developer line in
  a friend's build; a backup before Reset local cache; Claude's completion carries the full undo.

## Changes in behaviour George should know of

- Reminders: HITList asks for notifications the first time a task is given a reminder (once, unless reminders were
  already switched on or off in Settings).
- Two Groups, two labels or two filters can no longer share a name (the editor refuses).
- A label that is on tasks asks before it is deleted; Flipboard's own label cannot be deleted.
- Moving a task to Shared Tasks asks when the move would drop a label, repeat, reminder, deadline, location or
  ticked sub-tasks.
- Import JSON asks before bringing back what was deleted since the backup.
- Claude cannot clear a task's description without saying so (`clear_description`).
