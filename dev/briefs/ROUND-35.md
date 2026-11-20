# Round 35 (2026-11-20): the day George's own devices moved, and what he asked for after

Supervisor: Fable 5.2. One Opus 5.5 agent with a brief (174) and two read-only Opus reviewers. Version 0.9.17.
The night before is in `ROUND-34.md`, "Before release".

## The release and the move, as his Mac's log has it

George released 0.9.16 (build 31) on the morning of 2026-11-20 and moved his own Mac by hand, then his iPhone
followed by itself: the first devices on HITList's own sync in iCloud's Production side.

| When | What |
|---|---|
| 10:53 | First launch of 0.9.16 on the Mac, on the earlier sync. "Looked for the new sync's zone: not there", "not yet (no word)": nothing moves by itself, as meant. The bolt was not filled: 1 label and 2 filters exist only on this Mac (the three records stranded in October by Debug builds, known since round 27). |
| 10:55 | Seven clicks on the environment row; the "Sync engine" group appeared. He read its row "Everyone's move: Not released" as his own move having failed, and stopped. |
| 11:19 | A relaunch on which the earlier sync never imported ("iCloud isn't answering, HITList will keep trying"). |
| 11:22 | "Move to the new sync": the question warned "iCloud sync hasn't finished on this device … wait for the bolt". True of that launch (nothing compared since it), untrue of the Mac (a comparison four minutes earlier: nothing iCloud held that the Mac lacked), and on that Mac the bolt could never fill. He asked; told it was safe, he pressed Move anyway. |
| 11:26:15 | The move: backup `HITList-2026-11-20.json`, kept as "HITList before the new sync 2026-11-20.json"; "nothing shared an id"; the Mac relaunched itself 0.06 s after quitting. |
| 11:26:16 to :20 | On the engine: zone saved, 68 records accepted, fetched back, 67 "already as this device holds them", "Synced just now" 4.2 s after the relaunch. The three stranded records went with the rest. |
| after | His iPhone moved by itself once reopened (R2: its account's zone existed). Check iCloud…: no differences. Tasks added on each arrived on the other. No error or fault from the app in the Mac's system log since. |

His words: "Looks like it worked! The bolt is filled in and iCloud says synced. My iPhone also synced after I
reopened the app. Running Check iCloud noticed no differences. I tried a few tasks between iPhone and Mac and it
worked wonderfully. My only issue is that the bolt still goes hollow for a moment whenever a task is added on
either device; remember, the bolt is supposed to indicate to the user only when there's a pending problem or when
there's a successful resync after a long period away/outside of the standard sync window. For instance, if HITList
is currently syncing regularly and has been during that session, there's no need for the bolt to change. It should
then turn hollow and show the resync animation if the user closes the app/goes away for longer than a moment and
resync as needed. Let's run some tests to confirm everything landed how we expected and then start cleaning up all
these dev sync settings and logs so they won't be as easily visible to other users going forward."

He has not given the word for his friends (he said in round 32 that he wants some days on it first). Their
devices carry 0.9.16 and stay on the earlier sync.

## What the round did

**The bolt on the engine (the supervisor).** `SyncEngineSteadiness`, pure, fed by `CloudSyncMonitor`: a session
begins at a launch and when the app comes forward after a minute away (the strike's own "reopened"); the bolt is
hollow until a sync has ended after the session began, then fills, and that is when the strike may play; in a
session a change waiting, a send or a fetch shows nothing for eight seconds, the network gone or a sync that
stopped early for half a minute, each from its own start and all of it 38 s at most; a problem past its window,
a hold, refused items and no account show at once and end the session. `rawState` and the engine's own decisions
are untouched. A Mac app keeps its scene "active" when it is left for another app, so the monitor goes by
`NSApplication`'s own notifications there and asks for the session's sync itself.

The first version passed its tests and a live run. **A reviewer told to break it found six things**, the worst of
them old: the engine's first status of a launch reads "synced" before it has asked iCloud anything (it remembers
its first whole fetch across launches), so the bolt filled and struck before the launch's fetch (his log shows
the flash: 11:31:33.244 "Synced just now", .246 "Checking with iCloud…"). Also: an app launched in the background
by a push and opened hours later began no session; the network's return filled the bolt on the old sync before
the resync it asks for; one window measured across several kinds of work emptied the bolt at the moment of
recovery; a hold that cleared refilled on a sync from before it; `-syncEngineDemo synced` would have drawn
hollow. All fixed, each with a test; the fallback time for a "synced" with no sync behind it is gone
(`SyncEngineMarks.state` says checking).

Proved on iCloud's Development side with a Debug Mac build on a side store (`-syncEngine own -rehearsalEdits`):
at a launch the marks went "Checking with iCloud…", "Synced just now", once; six edits (two completions, a
rename, a move, a deletion, a new task) went and came back with no line of the marks changing; the check after
them: 149 records the same.

**Back online, what waited goes at once** (`SyncEngine.networkReturned`, asked by the monitor when the network
path returns): it used to wait for the pump's next try, up to ten minutes, or for the app to come forward. George
had asked whether a task added in airplane mode waits and then syncs.

**A side store's settings start empty** (`AppGroup.carriesOldSettings`): found by the UI tests on his iPhone.

**Settings → iCloud & data for a person who never heard how HITList syncs** (brief 174): see its report below.

## Tests run to confirm the release

The third of the UI suite that a closed lid cut short the night before was run on the released code
(`c5dcc0f0`) in a worktree of its own, two lanes: see "Proof".

## Proof

**The released build (0.9.16, `c5dcc0f0`).** The classes of the UI suite that the closed lid had cut short the
night before, from `HITListUITests`' last four to `WidgetsUITests`, in a worktree and derived-data folder of
their own, two simulators: 59 passed, 39 on demand, one failed. The one, `testFlipboardLightsStayOnTheirSwitches`,
counts the screenshots it can take in the 1.6 s after a tap and found three with two simulators and a build
running beside it (it needs more than three); alone it passed twice with seven. With the night's runs, every
class of the suite has passed on the released code.

## The bolt, reviewed twice

The first reviewer's eight findings are above ("The bolt on the engine"). The mended version went to a second,
who found all of them fixed and six more: time the process spent suspended, or the Mac asleep, counted against
what was under way (a task added as the phone was locked emptied the bolt on unlocking it half a minute later);
a Mac that slept in front of its person began no session; a fill with no sync behind it left the strike armed for
some later, unrelated fill; nine seconds of fetching counted as a problem; a window that ended with its sync
stamped and not yet heard of began a session after that sync; and an engine that never named its sync would
have left the bolt hollow for good. Each is fixed with a test, with tests for the rules of the type's header
that none had held. The second reviewer's verdict on what was left: by design. The live run was repeated on the
final code (a launch: "Checking with iCloud…", "Synced just now"; six edits: no line; 149 records the same).

## Brief 174: Settings → iCloud & data for a friend

What a person who never heard how HITList syncs now sees, iPhone and iPad, top to bottom: Sync (the status line;
a move the app made by itself, while it waits and for fourteen days after; on the new sync Sync now, what waits
while something does, what iCloud refused); the hold group when held; Backups; Export & Import; If something
doesn't sync (Check iCloud…, and the new Send sync log…, straight to the share sheet); Reset local cache… and
Delete all data from iCloud. The Mac's iCloud section: the same in its own layout, Send sync log… to a save panel.

Behind seven taps on Settings → About → Version, under "For troubleshooting" (footed "Shown because this device
was set to show them: Settings → About."): the environment row, Details, the Sync log's page, the last fetch and
send, Syncs through, "Friends' devices" (was "Everyone's move"), the move and its notes, and on the Mac the
inline log. About then shows "Troubleshooting rows: Showing", which hides them. The key is the old one, so
George's Mac stays revealed; a move asked for by hand and still waiting keeps the group up so it can be
cancelled; a Debug side store shows the rows as before (`-settingsAsFriend YES` shows it as a friend's).

The question before a move has three cases now: caught up, no warning; iCloud holds N items the device lacks,
the old warning with the number; not compared since the app was opened, words that say exactly that and point at
Check iCloud…. Check iCloud's own line lost "container", "zone" and "Development". A hosted test reads every
string an unrevealed person can reach, in many states, for the words that are not theirs.

Its pictures (31, before and after; read by the agent and by the supervisor) are in the notes folder,
`round-35/174/`. Its tests: 8 hosted (`TroubleshootingTests`), the move's three cases, and
`TroubleshootingRowsUITests` (the seven taps and the hiding; Send sync log… and its sheet; the page read from the
screen in four states).

**What it met and could not mend: the Mac test host reads the real app's settings.** `SyncEngineMoveFinishTests.
testNothingIsDoneUnderTests` failed on its tree and on master alike, because George's real store had moved that
morning and the test host (a Debug build in the real app's group, with no store suffix under tests) read his
preference. The supervisor read the preference back through the app's own entitlement (as he left it: the new
sync, no "stay", revealed) and gave a process that hosts tests a settings suite of its own
(`AppGroup.settingsSuffix`). One test had written to the real suite and taken it back in the same breath
(`MoveRedTeamTests`, the "stay" key); nothing else was found that wrote there.

Also from the agent: the Debug Mac app opened a window for it once and never again ("No windows open yet"), so
the Mac's "after" pictures are drawn by `ImageRenderer` in a hosted test (`MacICloudPicturesTests`, on demand).

## Left open, on purpose or for want of proof

- **The word for his friends**: his to give. Nothing in 0.9.17 changes how a store moves.
- **Whether the bolt now behaves as he meant**: proved by tests and on iCloud's Development side; judged by him on
  his own devices.
- A card left in the middle of a date word saves it as read so far; About is half below the fold on Settings'
  first screen on a 6.1-inch iPhone; "this monday" on a Friday; a sub-task typed and not entered is added when
  the app is left; UI tests that tap a row's middle under the screen's bottom edge fail on a real phone.
- The engine's first log line of a launch reads "Marks show: Local only: syncs on HITList's own engine…" before
  "Checking with iCloud…": the monitor writes it before it has heard its board; the bolt never draws it.
- `testFlipboardLightsStayOnTheirSwitches` counts screenshots in 1.6 s and fails with two simulators beside it.
- iOS 18 and macOS 15 were never run (no runtime here).
- Session "140 Sync engine: a pretend iCloud and its rig" still holds unmerged work.

**0.9.17, on the merged tree** (`75050548` and the notes after it): core 1,100 tests, the Mac 2,428, the iPhone
2,388, none failing. The whole UI suite, in two lanes on two simulators: 118 passed, 77 on demand, one failed,
`FlipboardPhoneUITests.testASwitchGroupedOntoABoardKeepsItsOwnTiming` (its drag did not land with the other lane
running beside it); alone it passed twice. Brief 174's own runs on its tree: its UI classes to their last test
(22 tests), and both hosted suites. The bolt's rules on iCloud's Development side, three times, the last on the
final code. Archive and export of both apps: see the hand-over.

Not proven: the bolt on an iPhone on the new sync (its coming forward is read in the source and held by the
rules' tests; George's own phone is where it is first seen); the Mac's activation and wake hooks in a running
app (the same); Send sync log…'s save panel on a real Mac (its sheet was seen on the iPhone simulator).
