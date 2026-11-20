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
