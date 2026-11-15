# Brief 143: the engine in the app, behind the switch (session `sync-wire`, effort xhigh)

HITList's own sync engine exists in parts on master (round 28, wave 1): the brain (`SyncCore`), the device's side
(`SwiftDataSyncStore`, `SyncLedgerStore`, `SyncSaveHints`), the road to iCloud (`CloudKitTransport`), and a pretend
iCloud for tests (`FakeCloud`). You put them together inside the app, **behind a switch that is off**: every released
build keeps SwiftData's mirror exactly as it is. With the switch on (a side store in a Debug build, this round) the
app runs on the engine from launch to quit.

**Clock** (Eastern, `TZ=America/New_York date`): a note to the supervisor at 06:00 (where you are, any question);
report by 06:50.

## Read first
`dev/briefs/COMMON.md` (the Round 28 block and its wave-2 addendum), `dev/briefs/ROUND-28.md`,
**`dev/SYNC-ENGINE.md`** (all of it), then in the notes folder the three reports written for you:
**`139-sync-core/REPORT.md`** (the brain's calls, the holds, `SyncHost`), **`141-sync-swiftdata/WAVE2.md`** (what the
store and the ledger need from you; writes are on the main context), **`142-sync-cloudkit/REPORT.md`** ("What the app
must do": launch, a push, the background), and `round-28/DATA-LAYER.md` sections 0, 2, 3.4, 4.3 and 5 (who writes
the store, what hangs on the mirror's events, how things are deleted and undone). Then the code:
`HITList/Services/SyncEngine/*`, `HITListApp.swift`, `ModelContainerFactory.swift`, `LocalCacheReset.swift`,
`Deduplicator.swift`, `LocalBackup.swift`, `AccountWatch.swift` and the account banner's code.

## Yours
New: `HITList/Services/SyncEngine/SyncEngine.swift` (and `SyncEngine+….swift`), `SyncEngineSwitch.swift`,
`SyncEngineHost.swift`; tests `HITListTests/SyncEngine/SyncEngine…Tests.swift`.
Edits, each as small as it can be: `ModelContainerFactory.swift` (which engine: how the store opens),
`HITListApp.swift` (start the engine; the scene phase), `SyncAppDelegate` (a push), `LocalCacheReset.swift`,
`Deduplicator.swift` (rows that share an `id`, for all six models), the background refresh's handler,
`WidgetCompletionCenter.swift` (what "sent" means on the engine), and the writers listed under item 6.

Not yours: `SyncEngineBoard.swift` (the supervisor's seam: you write to it, session 144 reads from it; a change you
need: ask), `CloudSyncMonitor.swift`, `SyncState.swift`, everything under `Services/Sync/`, the bolt's views and the
iCloud settings (session 144), everything in `HITListCore` (session 145 owns the brain and the rig now; a bug you
find in them: a failing test in your notes folder and a message to the supervisor at once), the models and
`HITListSchema` (no schema change), entitlements, `project.yml`, `scripts/`.

**iCloud is not yours to touch**: you never run the app with the engine against CloudKit. Everything you build is
proven on `FakeCloud` inside hosted tests and on a Debug Mac app whose engine is given the pretend iCloud (item 8).
The supervisor runs it against CloudKit Development.

## What to build
1. **Which engine** (`SyncEngineSwitch`): one answer per launch, decided before the container opens. `own` only
   when the store's preference says so (`AppGroup.defaults`, a key per store name) or a Debug launch argument says
   so on a side store (`-syncEngine own`; `-syncEngine mirror` wins the other way); never on the in-memory fallback,
   never under hosted tests unless a test asks. Default and every released build: `mirror`, and then **nothing of
   yours runs and nothing behaves differently** (prove it: with the switch off no engine object is made, no ledger
   file is created, the container opens exactly as today).
2. **The store on the engine**: the same store file opened without the mirror (`cloudKitDatabase: .none`).
   `ModelContainerFactory.isCloudKitEnabled` and its friends must say something true for both engines (list every
   reader of them and what each should see).
3. **`SyncEngine`** (one per process, main actor facade): makes the ledger for this store
   (`SyncLedgerStore.forAppStore`, bound to the store file's identity with `bind(toStore:)` before anything reads
   it: a bind that reset the ledger also resets the transport), the store (`SwiftDataSyncStore`), the transport
   (`CloudKitTransport`, container `SyncEngineSwitch.containerID`, today the tasks' container; a Debug argument
   `-syncEngineZone <name>` for the supervisor's runs; in tests a `FakeTransport`) and the brain; starts it; passes
   `ModelContext.didSave` hints on (`SyncSaveHintObserver`), re-reads what an apply wrote (141's WAVE2 point 8);
   on the app coming forward: `localChanged(nil)` and a sync; on a push and in the background refresh: a fetch
   (and a send) within the time the system gives; on quit: `stop()`. Publishes every status to
   `SyncEngineBoard.shared` and wires its `Actions`. One plain line per event into the board's log.
   Never wait for the brain synchronously on the main thread (141: it would deadlock with `apply`).
4. **`SyncEngineHost`** (`SyncHost`): `willRemoveLocalData` writes a backup (`LocalBackup`, as the pre-repair
   backups do) and throws if it could not; `didWrite` posts what the mirror's import posted
   (`.cloudKitImportSucceeded`: the name merge, reminders, widgets, Spotlight, the popout that closes, the day
   anchoring's pass all hang on it; read each consumer and say in your report that it still does the right thing
   when the writer was the engine) and `didAccept` what its export posted; the widgets' "the save has been sent"
   (`WidgetSyncFacts`) answered from the engine: the task's key accepted, or nothing waiting.
5. **Before the engine starts, and when it holds `duplicates`**: rows that share an `id` are merged for all six
   models (today's `Deduplicator` does three by `id` and name, and the profile; `TaskItem` and `Switchboard` never):
   the newest `updatedAt` stays, relationships re-pointed, nothing of the person's lost (a sub-task under either
   copy ends under the survivor); then `resume()`. The name merge after a fetch stays as it is.
6. **Writes that should move `updatedAt` and do not** (DATA-LAYER section 1.8; the engine orders two devices'
   changes by it): `Flipboard.restore` (an undo: `updatedAt` = now on what it puts back, so the undo beats the
   deletion it undoes and loses to a later one elsewhere), the notes set straight after a create (`QuickAddPopout`,
   `ShareInbox`, `ClaudeToolHandler`), `Flipboard.createSwitch`'s extra fields, a board's change re-landing its
   switches. One line each, a test each. `DayAnchoring` stays as it is (it is canonical and must not look like an
   edit).
7. **Reset local cache on the engine**: the store moved aside as today, the ledger forgotten with it (the binding
   does it; prove it), everything fetched again. The in-memory fallback: the engine does not run and the status
   says why. The move itself (`SyncEngineBoard.Actions.move`): a backup, the `id` merge, the preference, a
   relaunch (the Mac relaunches as Reset local cache does; the iPhone asks to be reopened); and the way back.
8. **Proof without iCloud**: hosted tests that run **two whole devices** (two in-memory SwiftData containers, each
   with a `SwiftDataSyncStore`, an in-memory `SyncLedgerStore`, a `FakeTransport` on one `FakeCloud`, a `SyncCore`):
   a task made on one appears on the other with its Group, labels and sub-tasks; an edit on each side of
   different fields both survive; a deletion; an undo; an edit in the main context while a fetch is being
   written; a "first sync" of two stores that already hold the same 500 items (nothing doubled, nothing sent
   twice); a sign-out and sign-in; Reset local cache. And a Debug argument `-syncEnginePretend` (side stores only)
   that runs the app's whole engine on a `FakeCloud` kept in a file in the notes folder you name, so two Debug Mac
   apps on two side stores can be driven by hand or by `scripts/window-drive.sh` and seen to sync: run that
   yourself, with pictures, and give the CPU of one at rest for a minute (`top -l 60 -s 1 -pid <pid> -stats
   pid,cpu`): 0.0%.

## Done when
The Mac suite passes (counts before and after) and your own classes pass on one simulator of your own
(`HITList-143`, deleted at the end); with the switch off a launch is byte-for-byte today's in what it opens and
logs (say how you checked); the two-device run is in your report with its pictures' paths; and the report lists
every consumer of the mirror's events and what feeds it on the engine, every choice the brief left you, what is not
built, and the exact commands for the supervisor's run of two Debug Mac apps on CloudKit Development.
