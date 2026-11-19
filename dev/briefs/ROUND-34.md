# Round 34 (2026-11-18, evening): 0.9.16, the build that moves everyone

0.9.15 was prepared that afternoon and not released. George that evening: "I've noticed there are still many
background tasks running. Is that okay? Those should be cleaned up whenever you're done with a release (along with
my desktop and temp files too as needed). I haven't released 0.9.15 yet because I want to be very confident in the
next build we release and I also want it to force everyone to move over to the new sync engine so we can settle
this once and for all. Before release, tell me clearly that both internal and external testers will safely retain
their task data after the move, or if I should tell them to download everything first. The iPhone is still a bit
slow, I notice it mostly when switching between home tabs and when browsing/swiping around the Settings menu. Take
another look using my connected iPhone if needed. Yes, please rewrite the repository if it's relatively easy to
scrub my personal information. Please take more time to prepare a build that is truly worthy of both the new sync
engine and to be sent to a wider group of friends."

## How it ran

The supervisor did the engine's work itself and briefed five Opus 5.5 agents with the Agent tool (briefs 168 to
172, committed first, each in its own worktree): two to build or measure, three whose only job was to find what
was wrong. No clock was set this time.

| Brief | What | Result |
|---|---|---|
| 168 `iphone-tabs-settings-speed` | The iPhone's tab switches and Settings, on George's phone | See "The iPhone" below: a probe that drives the app on the phone in a Release build; tabs kept alive halved a switch and doubled every save, so it was taken back |
| 169 `stranger-sweep` | Every screen a new person meets, in pictures, read by eye | 358 pictures (iPhone, iPad both ways, the Mac), 26 findings: one wrong date, the largest text size broken on six screens, the Mac's Week layout cut off in a narrower window; `StrangerSweepUITests` (on demand) |
| 170 `rollout-signal` | George's word that everyone may move | `SyncEngineRollout`: one record in the engine container's public database, pure rules, an asker with a stand-in, the schema file's new type |
| 171 `move-red-team` | "Lose a tester's tasks" | Twelve kinds of person walked through the move with the code open: round 33's "fresh copy" rule was unnecessary and the one way to hide everything; "caught up" left records behind; a pause split one person's devices; an untouched seed's stamp beat real changes. Four proof tests adopted into core |
| 172 `move-code-review` | The finished move's code, line by line | Eleven findings, three of them losses, one in the fix made for 171; a table of which rules no test would catch |
| 173 `large-text` | The accessibility text sizes | Dense controls stop growing at the first accessibility size (`HITType.controlSizeCap`): the week strip, the Week layout, Flipboard tiles, theme names, the card's pills, quick add's chips and their pickers; what a person reads still grows. XXXL pixel-identical. Left: Settings rows and section headers that should wrap at the largest sizes |

## The move (the supervisor's own work)

- **On, and waiting for his word** (`SyncEngineSwitch.movesByItself = true`; `SyncEngineAutoMove`,
  `dev/SYNC-ENGINE.md` section 14, stage 6). R0: a record of type `HLRollout` in the public database of the
  engine's container; any name; a record that says wait wins over every other. R1: only on the mirror, caught up
  (the bolt filled, or differences only on this device's side); a mirror that never catches up moves after seven
  days and three launches, and only once it has ended an import in that launch. R2: a device whose account's
  zone exists follows, whatever the word says. Always a merge: the "fresh copy" rule is gone.
- **It finishes itself** (`SyncEngineMoveFinish`): an iPhone ends its own process in the background, a Mac
  relaunches behind the other apps; never under a card, a sheet or an alert, never in a process the person has
  not had in front of them. **It checks itself** (`SyncEngineMoveCheck`): Check iCloud… once at rest, the result
  in the sync log and the group. **It keeps its backup** ("HITList before the new sync <day>.json", never rotated
  away, the first of its day).
- **From 172's reading**: on the mirror, rows of a task that share an `id` are never merged (two devices deleted
  each other's copy; the merge had been added that afternoon for 171); Reset local cache is not offered while a
  move waits; a default filter nobody changed takes the seed stamp before the engine starts; Cancel the move
  writes the "stay" key; a Debug build runs the move only where asked; the zone look gives up after thirty
  seconds; the rows that move a store show only where the group was revealed by the seven taps.
- **Rehearsed on iCloud's Development side**: the word (not yet, go, paused, limited to a build, a record of any
  name, cleared); a Mac side store that waits, then moves, 51 items the same; a first send of 6,005 records in
  24 batches, a minute and a half, the check the same; the Mac's own Development store, started in the
  background, moving, relaunching itself and checking itself (120 items the same); George's iPhone as the second
  device under a paused word: it found the zone, moved, ended its process when another app came forward,
  reopened on the engine, kept deleted what the Mac had deleted since, and both devices' checks said the same
  114 items.
- **The schema file gained `HLRollout`** (63 fields), imported into Development. Production needs George's
  deploy once more; `scripts/release.sh` stops until it has it.

## The supervisor's other changes

- **Cleanup**, on his word: 71 finished side sessions archived, 73 worktrees removed (110 GB), 86 merged local
  branches deleted, old build folders removed. It is a rule now (`dev/SUPERVISOR.md` section 3).
- **The history rewritten** and force-pushed: every commit authored "Aeronyx" with a GitHub no-reply address; the
  address, surname, home folder and App Store Connect ids out of every commit's content; an old tracked build
  folder dropped. A bundle of the old history is kept outside the repository.
- **A Debug build's side store had set George's real daily backups aside** on his Mac (its "account" is
  Development's, so it saw a switch): every writer of the backups folder now checks it runs on the real store.
  The thirteen backups are intact in the set-aside folder.
- **The Week layout keeps to the window it has** (from 169's pictures): its columns' widths came from a
  measurement of the stack that held them, so a window made narrower left the week at its old width, cut off on
  both sides. Measured on a ruler now; three days where seven do not fit. A hosted test draws it wide, narrow
  and wide again and fails on the old measurement.
- CI: the simulation's CPU bound allows for a slow runner (a push that changed nothing there had failed).

