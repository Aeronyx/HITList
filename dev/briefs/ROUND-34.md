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
- **From the sweep** (169's findings 1, 8, 9, 13, 15, 16, 19): "3 days ago", "2 weeks ago" and "last monday" are
  dates in the past (they were saved ahead, with "ago" left in the name); the Mac toolbar's capsule is as wide as
  its controls (Upcoming's third button hung out over the sync bolt); Account offers the sign-out row only where
  an account may be signed in; the words that send a person to sync's Settings page name the page they have; the
  iPad's "Add task" row has the list's own background; quick add's + menu says "Sub-tasks".
- What's New for 0.9.16 is seven lines (the page had grown to nearly two screens; the iPhone suite's own bound
  caught it).

## The iPhone (brief 168, then the supervisor on the phone)

Measured on George's iPhone 16 in a Release build by a probe that drives the app itself (`ResponseAutopilot`,
compiled into a Release build with `-D RESPONSE_PROBE`; `-responseAutopilot YES`): main-thread work from a change
to the frame that answers it.

| Store | Inbox | Today | Upcoming | Flipboard | add or check off |
|---|---|---|---|---|---|
| The demo week (about 20 tasks, 5 switches), iCloud off | 130 ms | 118 | 185 | 206 | 50 |
| 177 items and some forty switches, iCloud on, settled | 196 | 246 | 250 | 730 | 96 |
| The same after the lights' fix | 196 | 290 | 250 | 563 | 93 |
| 1,500 open tasks, iCloud off | 374 | 136 | 614 | 250 | 103 |

Settings: a page pushes in about 54 ms (the worst 98), goes back in 31, and no frame while scrolling any page is
longer than 21 ms; the sheet opens in about 180 ms the first time.

- **Kept tabs were tried and taken back** (168): a visited tab kept alive behind the one on show halved a warm
  switch (130 to 58–78 ms) and doubled every add and check-off (50 to 111–133), because the hidden lists redraw on
  each save; closing Settings went from about 50 to 130 ms, memory from 53 to 96 MB, and the hidden screens stayed
  in reach of VoiceOver and XCUITest. Nothing tried stopped the redraw. The shell builds the tab on show afresh,
  as before.
- **An overdue switch's light kept the phone busy** (found with iCloud on and a store that had grown some forty
  switches): each overdue pill was redrawn thirty times a second, 29 s of main-thread work a minute while the
  Flipboard was on show (4.7 s a minute with the demo's handful). Now the pill is drawn once dim and once lit and
  only the lit one's opacity is animated, by an animation scoped to that modifier (`BreathingPill`): 0.7 s a
  minute, and a warm switch to that Flipboard 730 ms to 563.
- **A switch to a tab costs with what the tab holds**: about 15 ms a Flipboard tile, and Inbox and Upcoming grow
  with the open tasks (the time is SwiftUI building the screen, not the app's own code: a sample of the simulator
  put a seventh of it in the app). Two changes in core that read less of each task (only a switch is asked for
  its board and toggles; a list's order reads each task once) cut the Inbox's choosing and ordering from 51 ms to
  10 for 1,500 tasks on the Mac and **changed nothing measurable on the phone**; they stay because they are
  proven the same and cost nothing.
- **George's own store is small** (his newest daily backup, counted only: 59 tasks, 6 of them open, 5 switches),
  so what he has is the first row of the table, and the 0.9.13 he is still on (nothing since was released) lacks
  round 32's and 33's work on the lists and tab switches. Not measured: 0.9.13 itself the same way (it has no
  probe), and his real store with the mirror running (a development build must not open it).

## Left open, on purpose or for want of proof

- **The engine has never run in iCloud's Production side.** George's own devices are its first: the Mac by hand,
  the iPhone following by itself, then his word.
- **Tab switches**: the structural fix is still owed. Two ways, neither small: Flipboard rows that build only the
  tiles on screen (its rows and sections are plain stacks, with drag and drop measured on them), and lists whose
  rows a rebuilt screen can take from a store kept above the tabs. Keeping whole tabs alive is not it (168).
- **The way back after the app's own move** (`dev/SYNC-ENGINE.md` section 13): a device that never moved follows
  its account into a zone everyone else left by hand; two devices that both came back with their own file hold
  the items made on the engine twice. The row that moves a store back shows only after the seven taps.
- 169's findings not acted on: an empty Today is one quiet line (a choice of an earlier round); a Group's long
  name is cut in its own title; the `flipboard` label shows among a person's labels (it is how a switch is one);
  the Claude page's words; a switch card's placeholder; Review Inbox's card on an iPad; the board's card with an
  empty second line; "Nothing due" under every empty day; the Week layout's small title on an iPad; an hour's
  name half under the band's edge when the grid opens between two hours.
- 173: at the largest text sizes Settings' row titles and the day headers break or truncate (rows a person reads
  should wrap there: a later round); the quick-add row cut at the first accessibility size could not be
  reproduced and is held by a guarantee and a test.
- 172's table of rules no test would catch: the query for the release record on CloudKit, the zone look's error
  mapping and the finish's observers are still proven only by rehearsal.
- Session "140 Sync engine: a pretend iCloud and its rig" holds unmerged work and stays open for George.

## Proof

On the final tree: core 1,100 tests, the Mac 2,380, the iPhone 2,341, no failures. Archive and export of both
platforms pass every packaging check, and the exported apps carry the feedback address. CI green on the push.
The move against iCloud's Development side, as listed above, twice with George's phone: the second time after
172's fixes (a fresh side store moved by itself, ended its own process with code 0 when another app came forward
while a tip was showing, reopened on the engine, 177 items the same in iCloud), and `MoveFinishUITests` holds on
a simulator that the app stays alive when left with Settings open and ends when left from its main screen. The
phone's numbers are in "The iPhone". The whole UI suite on the final tree, to its last
test: 190 tests, 114 passed, 76 on demand, none failed (a first pass on the tree as it was three hours earlier
had three failures, all three the fresh simulator's keyboard: two tests tapped while it slid, one sent a
Command-A no hardware keyboard delivered; the tests now wait until the screen is still and clear a field with
deletes). After it, one walk of the lists on an iPad for the "Add task" row.

Not proven: the engine in Production; the move on a real Mac's real store (the same code moved the Mac's
Development store and relaunched it); the CloudKit Console's own steps for making the record (written from what
the Console looked like when the schema was deployed, not seen this round); 0.9.13's speed measured the way
0.9.16's was; the iPad's and the Mac's pictures after 173's caps and the sweep's fixes beyond the ones named
(the Mac toolbar and Week layout were looked at in the running app, the iPad's "Add task" row in a picture).


## Before release (2026-11-20, the night after)

George: "Most of my friends' devices auto-update. Can I release this version safely? Test using my connected
iPhone if you haven't yet … I really want to ensure this build is a true precursor to a 1.0 release and that we've
performed rigorous regression testing for both UI/UX and backend purposes. Don't feel the need to redo any testing
you've already done, but I also don't want to lose my friends' trust in this app because we missed something
obvious before releasing this major build. Refresh your confidence and then tell me to deploy."

What "auto-update" changes: his friends' devices get the build before he has opened it on his own. So the
question is what an updated device does on its first day, with no move asked for. What was done, none of it a
repeat of the round's own proof:

- **The update itself.** The stored-data models and the way the store is opened are the same files as at
  `v0.9.13` (`git diff v0.9.13..HEAD -- HITList/Models`: only how long a set-aside copy is kept), so nothing is
  migrated. Then for real: 0.9.13 built from its tag in a worktree, a demo week seeded, the same store given to
  the simulator's ordinary store (`HITList-Development.store`, no test flags), opened by 0.9.13, every row of
  every table written out with `sqlite3`; this build installed over it and opened; the rows written out again:
  none differs (19 tasks, 5 Groups, 4 filters, 2 boards, 4 labels, 12 label links). The widget's snapshot and
  both extensions are unchanged since the tag, so a widget reads what 0.9.13 left until the app is next opened.
- **Three read-only reviews by Opus agents, each with one lens, on the diff since the last build friends have**
  (not since the last round): (1) everything that runs on a mirror device with no move asked for; (2) what the
  build says about itself (What's New, the notes) against what the code does, and logic in what changed; (3)
  whether the faster lists, counts and widgets can show something old. None found a reason to hold the release.
  (1) proved from the code that no record, a paused one, an error or an unknown type all mean "wait", that the
  word is never kept on disk, that the patience counters cannot run before the word, that the zone look reads
  the engine's own container and that nothing on a mirror device makes that zone; and that 0.9.13 could not have
  left a preference that reads as "moved". What they found and what became of it:

| Found | By | Became |
|---|---|---|
| Leaving the app with a card open ran a full Confirm: half-typed words read as dates ("Meeting at 1" → 01:00, then "Meeting0"), the space before the next word dropped | 2 | The space: fixed (`TaskEditorDraft.commitOnLeaving`: Confirm's save, then the title's and the description's last whitespace put back in the field; five tests). The half-typed word: **left, known.** The supervisor first replaced the save with one that stored the words unread and left the draft alone; its own second reading found it wrote an unedited title back over another device's edit (round 28's finding 5), and a fourth reviewer, given only that function, found that a whole "tomorrow" typed before leaving was then stored as plain words, undated, when the card was closed with ×, with lists, widgets and reminders showing the raw words meanwhile. Taken back the same hour |
| Week on iPad and Mac: "Previous week" live and dead on any day but the week's first | 2 | `UpcomingWeekWindow.canMoveBack(count:)` |
| Week: the open all-day band grew without limit and pushed the hours away | 2 | `UpcomingWeekView.openBandHeight`: six rows and a half (four at accessibility sizes), then it scrolls |
| The notifications question could be "asked" in the background and record a no nobody gave | 2 | asked only in front (`NotificationScheduler.isInFront`); a pass in the background marks nothing |
| Sidebar counts missed a switch falling due between saves (new since 0.9.13: the counts left the body) | 3 | `SidebarCountsModel` sleeps to `ListClock.next`, as the lists do |
| Details still said "the new sync (early access)" | 2 | gone; a test reads the app's sources for the words |
| Show completed might not rebuild a list's query (the switch is only passed down as a binding) | 2, unsure | it does: `testShowCompletedBringsBackWhatWasCompleted` on Today and the Inbox; no test had switched it on |
| The notifications question comes at the first launch after the update for someone with a reminder who was never asked | 1, 2 | left: it is the question round 32 meant; George is told |
| "Asked iCloud whether this device may move…: not yet" in the sync log every half hour of use | 1 | left |
| Reset local cache's backup overwrites the day's daily backup (as in 0.9.13) | 1 | left; next round: a file of its own |
| An account switched while the app was suspended keeps the earlier account's zone answer up to 30 minutes | 1, unsure | left: it is how a store moves (two reviews first), and it needs the word and a changed account |
| "this monday" on a Friday is the Monday just gone (as in 0.9.13, pinned by two tests) | 2 | left for George's taste |
| "last monday" and "2 weeks ago" read inside a longer name; "three days ago" not read | 2 | left |
| Week: a tap on an empty day does nothing; twenty tasks at one minute are slivers | 2 | left |
| "Week starts on" does not regroup an open list; the Mac's search does not take a task whose time passes | 3 | left (rare; next save or redraw) |
| Nested `Predicate` evaluation never run on iOS 18 or macOS 15 (the suites run on 26 and 27) | 1 | not proven; no older runtime is installed |

Lessons are in `dev/SUPERVISOR.md` (section 3's rules and "Lessons from round 34").
