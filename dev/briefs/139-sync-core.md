# Brief 139: the brain, `SyncCore` (session `sync-core`, effort xhigh)

HITList is getting its own sync engine (George: "I want it to be professionally built"). You build its brain: the
one actor that finds what changed on the device, settles what arrives from iCloud, keeps the engine's memory and
says what the bolt should show. It knows neither SwiftData nor CloudKit; it is pure Swift in `HITListCore` and is
tested by `swift test`.

**Clock** (Eastern, `TZ=America/New_York date`): a note to the supervisor at 04:30 saying where you are and any
question; report by 05:25.

## Read first
`dev/briefs/COMMON.md` (the Round 28 block), `dev/briefs/ROUND-28.md`, **`dev/SYNC-ENGINE.md`** (all of it, twice),
every file in `HITListCore/Sources/HITListCore/Sync/` (the contract: you build on it exactly as it is), and in the
notes folder `round-28/SDK-CKSyncEngine.md` sections 7 and 9 (what the real transport does and does not do for
you) and `round-28/DATA-LAYER.md` section 0 (what will surprise you about the app).

## Yours
New files only, in `HITListCore/Sources/HITListCore/Sync/`: `SyncCore.swift` (and `SyncCore+….swift` as you see
fit), `SyncStatus.swift`, `SyncHost.swift`; tests in `HITListCore/Tests/HITListCoreTests/Sync/`: `SyncCore…Tests.swift`
and your own scripted transport (`ScriptedTransport.swift`, a test double you drive by hand).

Not yours: the contract files (`SyncRecord`, `SyncSchema`, `SyncTransport`, `SyncStorage`, `SyncMemory`; a flaw:
write the diff in your notes folder and tell the supervisor at once, then work round it in your own files),
`RecordMerge.swift` (session 138 is proving it and may fix its inside; its public names stay), anything named
`FakeCloud` or `SyncSimulation` (session 140 builds the pretend iCloud; in wave 2 your brain runs on it, so keep to
the transport's rules T1 to T14 and nothing else), anything in the app.

## What to build
`public actor SyncCore: SyncTransportDelegate`, made from a `SyncLocalStore`, a `SyncLedger`, a `SyncTransport`, a
`SyncHost` (yours to define: the few things only the app can do, below), a clock (`@Sendable () -> Date`) and a
log (`@Sendable (String) -> Void`; one plain line per thing that happened, written for a person reading the sync
log: which record, which rule, why).

- **One thing at a time.** An actor's methods interleave at every `await`. A reconcile must never run in the
  middle of handling an event, nor two reconciles at once. Put every operation through one serial queue of your
  own inside the actor (and test it: a `localChanged` that arrives while a fetched batch is being written is done
  after it, on the state the batch left).
- **`start()`**: read the ledger; start the transport with yourself as its delegate; reconcile. **`stop()`**.
- **Finding what changed** (section 4): `localChanged(_ keys: Set<SyncKey>?)` (nil: everything). Compare the store's
  records with the ledger; set `deletedHereAt` when an item with a living base is gone; make the transport's
  pending list match (add what is missing, remove what no longer differs). Nothing is added before the first whole
  fetch has finished (section 7).
- **`recordToSend`**: the item as it is now with the ledger's token; the marker (at `deletedHereAt`) for an item
  deleted here; nil when there is nothing to send after all. `Meta/meta` when iCloud has none yet.
- **What arrives** (sections 5 and 8): `fetched` → for each record `RecordMerge.merge` → `LocalWrite`s with
  `expected` (a stale one is settled again on the newer record, a bounded number of times), in `SyncSchema.types`
  order, a record that points at something not here and not in the batch set aside until `didFetch`; `removed`;
  the echo of what this device just sent changes nothing. **Write the device first, then the ledger, and only then
  return from `handle`**: a crash in between leaves an item that differs from its base, which the next compare
  reads as a change to send, iCloud answers with a conflict, and the merge finds the two the same. The other order
  could send an old value over a new one. Prove both halves of that sentence with tests.
- **What comes back from a send**: `saved` → base and token; `failed` → `conflict` settled like a fetched record and
  added again if something is still to go; `unknownItem` (M11); `quotaExceeded` → hold; `tooLarge`, `rejected` →
  logged with the record's key, kept out of the pending list, shown in the status, never retried in a loop.
- **Holds** (section 10): `noAccount`, `needsUpdate`, `zonePurged`, `storageFull`, `duplicates`
  (`SyncStoreError.duplicates`), `failed`. Each has a way out that you define and test: `resume()` after the app
  merged duplicates; `answer(.removeHere | .keepAndSendAgain)` for a purge; a sign-in. Account changes and a lost
  zone as section 10 says, with `SyncHost.willRemoveLocalData(reason:) async throws` called (the app writes a
  backup) before anything of the person's is removed from the device, and nothing removed if it throws. A hold
  survives a relaunch (`LedgerFact.hold`).
- **`SyncHost`** also hears: which keys a fetch wrote to the device (the app posts what the mirror's import used
  to), which keys iCloud accepted, and every change of status.
- **`SyncStatus`** (`Equatable`, `Sendable`): the state (off, starting, idle, fetching, sending, held(reason)), how
  many changes are waiting, whether the first fetch has finished, when the last fetch and the last accepted send
  ended, the last error's words, and `isSynced` exactly as section 10 defines the filled bolt. Published as an
  `AsyncStream` (one value per change, the latest replayed to a new listener) and readable at any time.
- **`syncNow()`**: a fetch, then a send, for the person's "sync now" and for tests. Never from inside `handle`.
- Markers past `SyncSchema.markerLifetime` are removed for good (`PendingChange.delete`), and their ledger entries
  with them.

## Tests (the list is a floor)
On `MemoryLocalStore`, `MemoryLedger` and your scripted transport: each of T1 to T14 as the brain must meet it; each
row of section 10; every `SendFailure`; a fetch delivered twice; a fetch in two batches with a task before its
Group and before its parent; a reference to something that never arrives; an edit made on the device between the
read and the write; a crash after the device was written and before the ledger (make a new `SyncCore` on the same
store and ledger); a crash after the ledger and before the transport's bookmark (the event comes again); the ledger
thrown away (`reset`) on a device and on iCloud's side each holding data; `MemoryLedger.failNext()`; a delete then
an undo (the item made again with the same key before and after the marker was sent); 5,000 records reconciled
(give the time). Two brains on two stores wired to one tiny in-memory "iCloud" of your own are welcome if they are
cheap, but the many-device simulation is session 140's and wave 2's: do not build a second pretend iCloud.

## Done when
`cd HITListCore && swift test` passes (counts before and after); the report lists the public surface of `SyncCore`,
`SyncStatus` and `SyncHost` as wave 2 will use them, every place where the design left you a choice and what you
chose, and what is not built.
