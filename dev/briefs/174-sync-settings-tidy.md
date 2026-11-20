# 174: Settings → iCloud & data for a person who never heard how HITList syncs

Read `dev/briefs/COMMON.md` first (the two sections at its top, the "Round 35" block, the "Round 34 record"), then
this.

George, 2026-11-20, an hour after moving his own Mac and iPhone to the new sync in Production (it worked): "Let's
… start cleaning up all these dev sync settings and logs so they won't be as easily visible to other users going
forward." That morning two things on this page had already misled him, the person who asked for them: a row that
read "Everyone's move: Not released" ("it just said (not yet) after my 7 clicks so I assumed something didn't
work"), and a warning that told him to "wait for the bolt" on a Mac whose bolt could not fill.

## What the page is for

A friend opens Settings → iCloud & data (the Mac: Settings → iCloud, and Data) for four things: is it syncing,
keep a copy, bring a copy in, and "something is wrong, what do I do". Everything else on it today was put there
for George and the supervisor while the sync was being built. The first four stay in front; the rest goes behind
a gesture, whole and working, because George and the next supervisor still need it.

**Shown to everyone**

1. **Sync**: the status line as it is. On the new sync: Sync now, what is waiting when something is, and what
   iCloud refused when something was (a person has to see those). Not the times of the last fetch and send, and
   no "Sync log" row.
2. **The engine's hold group** when the new sync is held for the person (unchanged).
3. **Backups**, **Export and import**: unchanged.
4. **If something doesn't sync**: Check iCloud… as it is, and one new row, **Send sync log…**, which hands the
   log's file to the share sheet (iPhone, iPad) or a save panel (Mac) with no viewer in between: it is what
   George asks a friend for. Reuse what the log's own page does to export (`SyncLogView`); its subtitle says what
   the file is in a person's words ("What HITList did while syncing, to send to whoever is helping you").
5. **Reset local cache…** and **Delete all data from iCloud**: where they are, as they are.
6. **A move the app made by itself**: its one line while the device waits to join or to finish
   (`SyncEngineAutoMove.Runner.shared?.line`), and afterwards, for fourteen days, the line that says the other
   devices need the update (`SyncEngineAutoMove.otherDevicesNote`) with the check the device made of itself
   (`SyncEngineMoveCheck.line()`): in the Sync group, under the status line, not in a group of their own. If the
   date of the move is not stored anywhere you can read, store it the first time the line is shown (in
   `AppGroup.defaults`, a key of your own beside the group's) and count from there.

**Shown only where revealed** (and on a Debug side store, as now: UI tests depend on it)

- The environment row, Details, the Sync log's page (the viewer), the engine's last fetch and last send, and the
  whole "Sync engine" group: "Syncs through", the word for everyone, Move / Cancel / move back and their notes.
  A device on the new sync that was never revealed no longer shows that group at all (today it shows it "telling
  only").
- Give them one heading that says what they are, so nobody takes them for settings: a group titled **For
  troubleshooting**, footed "Shown because this device was set to show them: Settings → About."

**The gesture moves to Settings → About → the Version row**: seven taps, each within two seconds of the last
(`SevenTaps`, unchanged), the same key (`SyncEngineSwitch.revealedKey`: George's Mac is already revealed and must
stay so). Once revealed, About shows one row, "Troubleshooting rows: Showing", that hides them again when
pressed (it asks nothing; seven taps bring them back), so George can see the page as a friend sees it. The
environment row loses its tap gesture.

**Two things to reword inside the revealed group** (George read both wrongly on 2026-11-20):

- "Everyone's move" / "Not released" told him his own move had failed. It is the word he gives his friends. Title
  it **"Friends' devices"**, with values "Asking iCloud…", "Not moving yet: you have not given the word", "Moving
  by themselves", "Paused", "Couldn't ask iCloud".
- The question before a move warned "iCloud sync hasn't finished on this device … Better: wait for the bolt, then
  move" on a launch where the earlier sync had not yet fetched and nothing had been compared (his log: no import
  since the relaunch, "iCloud isn't answering, HITList will keep trying"), four minutes after a comparison that
  found nothing iCloud held and the Mac lacked. Say what is known. Three cases, from what
  `CloudSyncMonitor.shared` already publishes (`state`, `recordDifference`; read them, change nothing in that
  file): caught up (`SyncEngineAutoMove.caughtUp`): no warning, as now. Compared, and iCloud holds something
  this device lacks (`SyncEngineAutoMove.leftBehind(...) > 0`): today's warning, with the number. **Not compared
  since this launch** (anything else): "HITList has not compared this device with iCloud since it was opened, so
  it cannot say that everything has arrived. Check iCloud… (above) compares them now. Moving anyway is safe if
  nothing was changed on another device in the last few minutes: a deletion made there would come back." Keep
  "Move anyway".

## Words

Nothing an unrevealed person can reach on these pages says CloudKit, environment, Production, Development,
engine, zone, mirror, ledger or transport. Walk every string on the unrevealed page (the status line's words in
`SyncWords` included, for the mirror and for the new sync) and fix what does; list each change in your report.
"The new sync" and "the earlier sync" are the names where a name is needed at all; after the move a friend
should rarely need one.

## Bounds

- **Yours**: `HITList/Views/Settings/**`, `HITList/Views/SettingsView.swift`, the words in
  `HITList/Services/Sync/SyncWords.swift`, the hosted and UI tests that cover these pages
  (`SettingsTidyUITests`, `SyncEngineStatusUITests`, `MoveFinishUITests`' way to the row, `SettingsTests`,
  `SyncEngineWiringTests`' words, the sweeps' walks of these pages).
- **Not yours**: `CloudSyncMonitor.swift`, `SyncState.swift`, anything under `HITList/Services/SyncEngine/` and
  the bolt's views (the supervisor is in them this round, making the bolt steady); how a store moves; `WhatsNew`,
  `CHANGELOG.md`, the version. If you need something those files do not give you, say so in your report and
  leave the row as it is.
- The Mac's Settings is a different layout (`HITList/Views/Settings/Mac/`): the same rule there.
- A simulator of your own named `HITList-174` (iPhone 17) and a derived-data folder of your own
  (`build.noindex/174`); the Mac through `scripts/window-shot.sh` on your own Debug build with a side store.
  Delete the simulator and the folder when you finish. Nobody's phone.

## Proof (yours to make and to look at)

- Pictures, before and after, saved in the supervisor's notes folder
  (`~/Library/Application Support/Claude/side-session-notes/local_8995b93d-4779-400a-855f-77db7b4e0b1d/round-35/174/`):
  iCloud & data on the iPhone on the earlier sync and on the new sync (`-syncEngineDemo synced`, and one with
  something waiting), unrevealed and revealed; About before and after the seven taps; the Mac's iCloud section
  unrevealed and revealed. **Read every one yourself** and say in the report what a friend now sees, top to
  bottom, in a few lines.
- Hosted tests for what holds without a picture: what shows revealed and unrevealed on each sync; the three
  cases of the move's question; the fourteen days; the words (a test that reads the unrevealed page's strings for
  the forbidden words is worth its lines).
- A UI test that taps About's version seven times, sees the group arrive in iCloud & data, hides it again from
  About, and sees it gone; one that presses Send sync log… and sees the share sheet.
- `SIMULATOR=HITList-174 scripts/test.sh ios` and `scripts/test.sh macos` green on your tree, and the UI classes
  named above, to their last test, before you report.
- Commit each item the moment it is whole. No push, no merge, no `scripts/release.sh`.

## Report

What a friend sees now, top to bottom, iPhone then Mac; what is behind the gesture; each string changed; what you
could not do within your bounds and what it needs from the supervisor's files; pictures' folder and count; tests
and their counts; your branch and commits; your simulator and folder deleted.
