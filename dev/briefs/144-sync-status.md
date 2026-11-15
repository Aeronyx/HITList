# Brief 144: the bolt and Settings → iCloud on the engine's own status (session `sync-status`, effort xhigh)

HITList's own sync engine knows exactly what the mirror never told: how many changes are waiting to go, whether
the first fetch has finished, and why it is holding when it holds. You make the app show that, when a launch runs
on the engine. On the mirror (every released build) nothing you touch may look or behave differently.

**Clock** (Eastern, `TZ=America/New_York date`): a sheet of pictures to the supervisor by 06:10 (George judges
from pictures: the bolt's states and the iCloud page, Mac and iPhone, at real size); report by 06:50.

## Read first
`dev/briefs/COMMON.md` (the Round 28 block and its wave-2 addendum; **Round 26's and Round 27's rules on the bolt
still bind you**: no timer with nothing pending, no animation without an end, nothing endless in the Mac's toolbar,
a CPU reading in your report), `dev/briefs/ROUND-28.md`, `dev/SYNC-ENGINE.md` (sections 1, 4, 10, 12), in the
notes folder `139-sync-core/REPORT.md` (`SyncStatus`, `SyncHold` and "What the app should show"), then
`HITList/Services/SyncEngine/SyncEngineBoard.swift` (**your one source**: the engine's status and the actions a
person can ask for), `CloudSyncMonitor.swift`, `SyncState.swift`, `Services/Sync/SyncWords.swift`,
`Support/SyncStatusViews.swift`, `Views/Settings/ICloudSettingsGroups.swift`, `SettingsView.swift`'s page rows,
`Views/Settings/Mac/*` for the iCloud section, and the design system README. George's standing words on layout:
text is never near a border (floors 12, 8 and 6 pt), and a status must say something a person can act on.

## Yours
`CloudSyncMonitor.swift` (a branch for the engine: `state` and its words come from the board, and none of the
mirror's instruments run), `SyncState.swift` (cases the engine needs), `Services/Sync/SyncWords.swift`,
`Support/SyncStatusViews.swift`, `Views/Settings/ICloudSettingsGroups.swift`, `SyncLogView.swift`,
`Views/Settings/Mac/LastSyncChange.swift` and the Mac's iCloud section, the iCloud row's subtitle in
`SettingsView.swift`; new `HITList/Views/Settings/SyncEngineSettings.swift`; tests beside the existing ones
(`HITListTests/SyncEngineStatusTests.swift` new; `SyncRecordCheckTests` and the bolt's existing tests stay green
untouched).

Not yours: `SyncEngineBoard.swift` (the supervisor's seam; a change you need: ask), every other file in
`Services/SyncEngine/` (session 143 runs the engine and writes to the board; you never call the engine), everything
in `HITListCore`, `Deduplicator.swift`, `ModelContainerFactory`, `HITListApp.swift`, `WidgetCompletionCenter.swift`,
the models, `WhatsNew.swift`, `scripts/`.

## What to build
1. **One switch at the top of the monitor**: when `SyncEngineBoard.shared.engine == .own`, `CloudSyncMonitor`'s
   published `state`, its words, `isChecking`, `lastSyncedAt` and the rest of what views read are worked out from
   `SyncEngineBoard.shared.status` (and the account and the network, which the monitor still watches) by **one
   pure function** you can test with every status; the session gate, the record check, the watchdog and the
   steadiness built round the mirror do not run and arm no timer. On the mirror: byte for byte as today.
2. **What the bolt says on the engine** (`dev/SYNC-ENGINE.md` section 10):
   - filled: exactly `status.isSynced` ("Synced just now", as today);
   - changes waiting: hollow, in the theme's tint, with the number in the words: "3 changes waiting to go to
     iCloud" (1: "1 change waiting…"); while a send is under way the same words; offline: "… they go when you are
     back online";
   - before the first fetch has finished: "Checking with iCloud…" (hollow);
   - a hold: hollow, and red only for the ones a person must act on (`massDeletion`, `zonePurged`, `needsUpdate`,
     `storageFull`, `failed`; not `noAccount`, which is today's signed-out state), with words a person
     understands and no jargon: "248 items are missing from this device. Nothing has been deleted in iCloud.",
     "HITList's data was removed from iCloud in Settings.", "Update HITList to sync: iCloud holds data from a
     newer version.", "iCloud is full: 12 changes are waiting.";
   - `lastError` (a sync that stopped early) as today's retrying state, never red in the first minute;
   - items iCloud refused for good (`refused`): the iCloud page names them.
   No "Sending", no spinner that does not end, nothing that animates while it waits.
3. **Settings → iCloud on the engine** (iPhone, iPad, Mac): the status line; "Sync now" (the board's `syncNow`;
   its error in words); a hold's own group with its buttons and what each will do, said before it is pressed:
   mass deletion ("I deleted them" / "Keep them in iCloud", the second explaining Reset local cache), a purge
   ("Remove from this device too" after a backup / "Keep here and send to iCloud again"), a failure or a full
   iCloud ("Try again"), duplicates (nothing to press: "tidying up"); the count of what is waiting; when the last
   fetch and the last accepted send ended. Check iCloud… and the record-check note are the mirror's: hidden on the
   engine this round (say so in the code). The sync log shows the engine's lines (`SyncEngineBoard.onLog` into the
   monitor's one door, `write`).
4. **The switch's row**, for Debug builds on a side store only this round (hidden everywhere else, and say in the
   code that showing it to testers is George's decision): "Sync engine: iCloud's mirror / HITList's own", what
   moving does in two sentences, and a button that calls the board's `move` and shows its error. No engine code.
5. **A way to see every state without an engine** (Debug, side stores): a launch argument `-syncEngineDemo
   <state>` that calls `SyncEngineBoard.shared.show(_:)` with a made-up status (`synced`, `waiting3`, `checking`,
   `mass248`, `purged`, `update`, `full12`, `failed`, `refused2`, `signedout`). Your pictures and UI tests use it;
   session 143's engine is not needed for any of your work.
6. **Pictures**: one sheet for the Mac (the toolbar's bolt in each state at 1x beside the iCloud section for the
   four states that have buttons) and one for an iPhone 16 simulator of your own (`HITList-144`): the bolt where it
   shows and Settings → iCloud & data for the same states. Sent to the supervisor by 06:10 with one line on
   anything you are unsure of.

## Done when
The Mac suite passes (counts before and after), your classes pass on your simulator (deleted at the end), a Debug
Mac build in each demo state for a minute at rest reads 0.0% CPU (give the numbers), the bolt on the mirror is
unchanged (the existing tests untouched and green; say how else you checked), and the report lists the words for
every state, every choice the brief left you and what is not built.
