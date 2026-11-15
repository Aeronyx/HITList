# Brief 142: the road to iCloud on `CKSyncEngine` (session `sync-cloudkit`, effort xhigh)

HITList is getting its own sync engine (George: "I want it to be professionally built"). Its brain speaks to
iCloud through a protocol (`SyncTransport`). You build the real implementation, on Apple's `CKSyncEngine`, and
prove it against CloudKit's Development environment. Nothing you build is switched on in the app this round.

**Clock** (Eastern, `TZ=America/New_York date`): a note to the supervisor at 04:30 saying where you are and any
question; report by 05:25.

## Read first
`dev/briefs/COMMON.md` (the Round 28 block), `dev/briefs/ROUND-28.md`, **`dev/SYNC-ENGINE.md`** (sections 2, 3, 6
and 10), every file in `HITListCore/Sources/HITListCore/Sync/` (the contract: `SyncTransport.swift` is what you
implement, exactly as it is), in the notes folder **`round-28/SDK-CKSyncEngine.md`** (all of it: the API as this
Mac's SDK has it, what the engine does for you and what it leaves to you, the traps in Apple's own comments),
then `HITList/Services/Sharing/SharedTasksSync.swift` (a `CKSyncEngine` already in this app, for another container:
the house style for its delegate and its state) and `round-28/DATA-LAYER.md` sections 4 and 10 (what touches
CloudKit today; entitlements).

## Yours
New files only: `HITList/Services/SyncEngine/CloudKitTransport.swift`, `CloudRecordCodec.swift`,
`SyncTransportProbe.swift` (Debug builds only); tests `HITListTests/SyncEngine/CloudRecordCodecTests.swift`,
`CloudKitTransportTests.swift`. Run `xcodegen generate` after adding files.

Not yours: the contract files in core (a flaw: the diff in your notes folder and a message to the supervisor at
once), entitlements and `project.yml` (the engine needs CloudKit and remote notifications; both are there; if you
believe something is missing, say so and stop short of changing it), everything under `Services/Sync/`,
`CloudSyncMonitor.swift`, `Services/Sharing/*`, `ModelContainerFactory`, the models,
`HITList/Services/SyncEngine/SwiftData*.swift`, `SyncRecordMapping.swift`, `SyncLedgerStore.swift`,
`SyncSaveHints.swift` (session 141, in the same new folder), `scripts/`.

## What to build
1. **`CloudRecordCodec`**: `SyncRecord` ↔ `CKRecord`, driven by `SyncSchema`.
   - The record's name in CloudKit is `"<type>.<name>"` (`TaskItem.6B1F…`, `Profile.profile`, `Meta.meta`) in zone
     `SyncSchema.zoneName` of the private database: a pending change names a record by its `CKRecord.ID` alone, and
     the id must say the type. Parse it back strictly; a record whose name does not parse is ignored and logged.
   - Out: every field of the type set or set to nil (T4), `deletedAt` likewise; a key the type does not list is
     never touched. Kinds: string; int as `Int64`; bool as `Int64` 0 or 1; date as `Date` from whole milliseconds;
     `data(asset: false)` as bytes, `data(asset: true)` as a `CKAsset` (a temporary file you remove when the send
     has ended, on every path); a reference as the other record's key name (a string), references as `[String]`.
     Never a `CKRecord.Reference`: iCloud must not delete or refuse anything on its own account.
   - The record to send is rebuilt from `system` (`encodeSystemFields` unarchived) when there is one, so iCloud
     sees the change tag; made new when there is none.
   - In: every key that maps to a `SyncValue` (known to the schema or not, so the brain can cut it down; an asset
     read into bytes, with a size limit you choose and state), dates rounded to milliseconds, `system` from
     `encodeSystemFields`. Tests: every field of every type there and back; a record with keys from "a newer
     build" survives a rebuild-and-save untouched (assert on `changedKeys()`); the bool and the date edges.
2. **`CloudKitTransport`** (`SyncTransport`) on `CKSyncEngine`, made from a container id, a `SyncTransportState`
   and a log. `State.Serialization` is saved through `SyncTransportState` on every `stateUpdate`, and given back
   at `start`. Fetches and sends are **scoped to the engine's zone** (`nextFetchChangesOptions`, and
   `context.options.scope.contains` when building a batch): the mirror's zone lives in the same database and its
   records must never reach the brain. Batches with `RecordZoneChangeBatch(pendingChanges:recordProvider:)`, never
   atomic. The zone: `.saveZone` queued when there is something to send and the zone is not known to exist, and
   again on `zoneNotFound` (the refused saves re-added by you; the brain is not told). Map every event and every
   `CKError` onto `TransportEvent` and `SendFailure` exactly as T1 to T14 say; write the table in your report
   (code → what the transport does → what the brain is told). The seven codes the engine retries itself are T5.
   `serverRecordChanged` → `conflict` with the server's record; `unknownItem` on a save → `unknownItem`, on a
   delete → done; `quotaExceeded`; `limitExceeded` (the batch initialiser sizes batches: say what you do if it
   still happens); a zone deleted, purged or reset (from `fetchedDatabaseChanges`, from `userDeletedZone`, from
   `zoneNotFound` with `CKErrorUserDidResetEncryptedDataKey`) → `zoneLost`; `accountChange` → `account(…)` with the
   user record names. `pending()` from the engine's state, names parsed back to keys. `reset()`: a new engine with
   no state. `automaticallySync` is a parameter (true in the app, false in the probe and in tests).
   What can be unit-tested without a server is little (the SDK lets a test build no event): keep every decision in
   small pure functions that take your own values (an error code and its userInfo, a record id) and test those.
3. **The probe** (`SyncTransportProbe`, `#if DEBUG`, launch argument `-syncTransportProbe` on a side store only:
   refuse to run when `ModelContainerFactory.isMainStoreOpen`): proves the transport against CloudKit
   **Development** with two `CloudKitTransport`s in one process as two devices (two engines on one database are
   allowed in Development, section 9.10 of the SDK notes), each with its own in-memory `SyncTransportState`, in a
   **zone of its own** (pass the zone name in: `HITListProbe-<random>`; the engine's real zone is not touched) that
   it deletes at the end, also when it fails. Script: device A saves one record of every type carrying every field
   (this is also how Development learns the new record types and fields); B fetches them and they are equal; B
   changes one, A changes the same one without fetching and gets `conflict` with B's version; A saves a marker; B
   fetches it; a save with a token for a removed record gives `unknownItem`; a key written "by a newer build"
   survives a save by the transport; 300 records go in two batches; the state saved by A, a new transport made
   from it, a fetch brings only what changed since. Each step one line in the log (`category: sync`) and on
   stdout: `PROBE ok <step>` or `PROBE FAIL <step>: <why>`, then `PROBE done N ok, M failed`.
   Run it: a Debug Mac build of your own (`-derivedDataPath build.noindex/mac-s142`), launched from the shell with
   `HITLIST_STORE_SUFFIX=s142` and `-syncTransportProbe -ApplePersistenceIgnoreState YES` and **without**
   `-disableCloudKit` (the probe needs iCloud; the app's own mirror then also syncs that empty side store to
   Development, which is harmless test data). Signed Debug builds talk to Development only; never run a Release
   build, never the real store, never Production. If iCloud asks for anything on screen, do not answer it: say so.
   Put the probe's whole output in your report. If the run cannot be made (no account, a dialog), say exactly what
   you saw and how the supervisor can run it.
4. **For the release guard later**: in your report, the list of record types and fields the probe created in
   Development, as CloudKit's schema names them, so wave 2 can teach `release.sh`'s guard about them.

## Done when
The Mac tests pass (counts before and after, your classes named), the probe's output is in the report, and the
report has: the error table of item 2, what the SDK left unsaid that you had to find out by running (the echo of
a device's own saves on its next fetch: does it come? does the app have to register for remote notifications?
what happens to a pending save whose record provider returned nil?), every choice the brief left you, and what
wave 2 needs to wire the transport into the app's life cycle (launch, a push, the background).
