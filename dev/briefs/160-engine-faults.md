# 160: the engine's faults from round 32's reviews, fixed (code)

`dev/SYNC-ENGINE.md` section 14, stage 2 ("no open finding that can lose a person's change"). Reviews 148 (the
transport against Apple's documentation) and 147 (the engine on the real store) found these; 149 and 150 have
merged, so the brain and the transport are yours now. The reports are in the notes folder:
`round-32/148-transport-review/REPORT.md`, `147-engine-live-review/REPORT.md`, `149-transport-hardening/REPORT.md`,
`150-sim-limits/REPORT.md`.

**What changed under you tonight** (found with George's iPhone beside this Mac; read the comments at the places
named before you touch them, and keep them): Apple's engine runs with its own scheduling **off**
(`SyncEngine.launchIfSwitchedOn`: `automaticallySync: false`; with it on, a fetch after a relaunch never asked
iCloud what changed), so the app's engine asks for each sync itself (`SyncEngine.pumpAfter`, `syncSoon`,
`SyncEnginePumpTests`): rule T5's "the transport tries again by itself" is now kept by that pump, and a hold arms
nothing. A manual fetch asks for every zone (`.all`) and `nextFetchChangesOptions` keeps the records to this zone.
The transport saves a push subscription of its own (`ensureSubscription`), and a reset replaces the engine before
the forgotten state is written (148's finding 4: done, leave it). Each fix with a test written first and
seen to fail; the simulation (`SyncCoreSimulationTests`, the commands at the top of that file) green at the end.

**Yours**: `HITListCore/Sources/HITListCore/Sync/` and its tests; `HITList/Services/SyncEngine/` except
`SyncEngine+Move.swift`, `SyncEngineSwitch.swift`, `SyncEngineAudit.swift`, `SyncEngineRehearsal.swift` (the
supervisor's); in `HITList/Views/Settings/SyncEngineSettings.swift` only `SyncEngineWords` and the hold group's
switch statements (a new hold needs its words and its button); `HITList/Services/Sync/SyncWords.swift`,
`HITList/Services/SyncState.swift` (the engine's marks only), `HITList/Services/Sync/AccountSwitch.swift`,
`HITList/Services/CloudSyncMonitor.swift` (the account switch's lines only), `HITList/Services/LocalBackup.swift`
(`setAside` only); tests in `HITListTests/`. **Not yours**: `dev/SYNC-ENGINE.md` (give the words for sections 5, 6,
10 and 13 in your report), anything else.

**Do not run the transport's probe** (`-syncTransportProbe`): it writes a field of its own into the engine's
container's Development schema on purpose, and that schema was put into its final shape on 2026-11-16
(`dev/cloudkit/sync-engine.ckdb` imported) for George to deploy to Production. Nothing of yours needs CloudKit.

In this order:

1. **iCloud refusing the whole send must hold, never refuse each record for good** (148 finding 1). In Production an
   unknown record type or field is refused per record with `invalidArguments`; a container, entitlement, permission
   or version error says the same about the build or the account, not about the record. Today each such record is
   "refused for good" and kept out until the person changes it: a schema not yet deployed would park a whole store
   until a relaunch. Map these codes (148 lists them) to a failure of their own; the brain holds with the server's
   words in the log and plain words for the person ("iCloud isn't ready for this version of HITList yet. Nothing is
   lost: what is waiting stays waiting."), everything still waiting and counted, nothing refused, tried again on
   return to the app and by "Try again", never by a timer (the path `storageFull` already has: use it, do not
   build a second one). The zone's own record (`Meta/meta`) honours a refusal like any other. The bolt's marks and
   Settings → iCloud show the hold as they show a full iCloud.
2. **A deletion's note is forgotten while its save is still committing** (148 finding 3): the brain forgets only
   the notes of deletions it took up (`told` less the keys still on the device), and leftovers are cleared at the
   launch's whole compare. A test that interleaves two deletes as the finding describes.
3. **A hold's words** (147 F10): the person never reads a Swift error or the words "engine", "ledger" or "memory":
   fixed plain words per failure ("HITList couldn't save its sync records on this device."), the error itself in
   the sync log only.
4. **`internalError` and the asset-file errors are passing trouble**, not refusals for good (148, polish).
5. **What 149 left for the brain** (its report: "the brain gap"): while the transport owes a record it could not
   read, the brain keeps a deletion of its own that has no base for that key (the first whole fetch would otherwise
   drop it and the item would come back when the record becomes readable), and a refused key is cleared when a
   fetch moves its base. Only if each is a few lines; say what you left.
6. **`ensureSubscription` can run twice at once** (two fetches in flight both find it unsaved): once.
7. **An account switch has two owners that race** (147 F6): on the engine the one order is: the brain's backup; the
   previous account's backups set aside (by the host's backup itself, which does not mark the day's backup done);
   the brain removes and forgets; the monitor's `handleSwitch` does the rest and skips its own setting aside; the
   brain joins and fetches. **And items iCloud never held are not carried into another account** (147 F11): at a
   switch to a different account they leave with the rest, after the same backup. A sign-out stays as it is built
   (what was synced leaves the device after a backup and returns at sign-in: George decides separately whether a
   sign-out should keep the tasks on the device; change nothing there).

Proof: `swift test` in `HITListCore`; 300 histories of every fault set of the simulation with no failure that is not
one of 150's written limits (give the counts); the Mac's hosted tests in `HITListTests/SyncEngine` and
`SyncEngineStatusTests`, and the whole of `HITListTests` once at the end (`-derivedDataPath build.noindex/160`).
