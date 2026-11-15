# Brief 141: the device's side: the models as records, and the engine's memory on disk (session `sync-swiftdata`, effort xhigh)

HITList is getting its own sync engine (George: "I want it to be professionally built"). Its brain speaks in
records (`SyncRecord`) and knows nothing of SwiftData. You build the two things in the app that it stands on: the
six models read as records and records written back (`SyncLocalStore`), and the engine's own memory kept on disk
(`SyncLedger`). Nothing you build is switched on in the app this round: it is proven by tests.

**Clock** (Eastern, `TZ=America/New_York date`): a note to the supervisor at 04:30 saying where you are and any
question; report by 05:15. Build the Mac tests first; one simulator run of your own test classes near the end.

## Read first
`dev/briefs/COMMON.md` (the Round 28 block), `dev/briefs/ROUND-28.md`, **`dev/SYNC-ENGINE.md`** (sections 2 to 5
and 8), every file in `HITListCore/Sources/HITListCore/Sync/` (the contract: `SyncStorage.swift` is what you
implement, `SyncMemory.swift` shows the behaviour in forty lines, `SyncSchema.swift` is the field table),
`HITList/Models/Models.swift`, `ModelContainerFactory.swift`, `SchemaVersions.swift`'s header, and in the notes
folder **`round-28/DATA-LAYER.md`** (all of it: sections 1, 3, 5 and 6 are about exactly what you touch; section
0's points 2, 8, 9 and 12 will bite) and `round-28/SDK-SwiftData-History.md` (what `didSave` carries, as observed).
Session 138 will put in its notes folder (`138-sync-proof/`) the property list it derived for your schema test;
look for it at 04:15, and write the test from the models yourself if it is not there.

## Yours
New files only: `HITList/Services/SyncEngine/SwiftDataSyncStore.swift`, `SyncRecordMapping.swift`,
`SyncLedgerStore.swift`, `SyncSaveHints.swift`; tests `HITListTests/SyncEngine/SwiftDataSyncStoreTests.swift`,
`SyncRecordMappingTests.swift`, `SyncLedgerStoreTests.swift`. Run `xcodegen generate` after adding files (the
project file is generated; the supervisor regenerates it at the merge).

Not yours: the models and their schema (**no change to any `@Model`, no new entity in `HITListSchema`**: the
ledger has a store and a schema of its own), `ModelContainerFactory`, everything under `Services/Sync/` and
`CloudSyncMonitor.swift` (the mirror's side, untouched this round), the contract files in core (a flaw: the diff in
your notes folder and a message to the supervisor at once), `HITList/Services/SyncEngine/CloudKit*.swift` and
`CloudRecordCodec.swift` (session 142, in the same new folder).

## What to build
1. **The mapping** (`SyncRecordMapping`): each model to a `SyncRecord` and back, driven by `SyncSchema.types` so
   that a field is named once. Dates through `SyncValue.date` (whole milliseconds). A relationship is the other
   item's `id.uuidString` (`labels`: `SyncValue.references`); `Profile`'s key is `SyncSchema.key(profile, …)`
   whatever its row's `id`. Empty optionals are absent; required fields always present.
   **The test that keeps the table honest**: walk `HITListSchema.schema`'s entities (attributes and relationships,
   not the inverse to-many sides: `Project.tasks`, `TaskLabel.tasks`, `Switchboard.switches`, `TaskItem.subtasks`
   are the other end of a field that is in the table) and fail when a stored property is missing from
   `SyncSchema`, has another kind, or the table lists something the model lacks; `id` is the key, not a field. A
   model that gains a property must fail this test until the table has it.
   Every field of every model there and back, at its edges (an empty string, a date with sub-millisecond digits,
   a 200 KB picture, twelve labels, a sub-task, a switch on a board).
2. **`SwiftDataSyncStore`** (`SyncLocalStore`) on the app's `ModelContainer`, with a context of its own, off the
   main actor (a `@ModelActor` or your own serial executor; say which and why).
   - `records()` and `records(_:)`: what is saved now. Two rows with one key: `SyncStoreError.duplicates` with the
     keys (several `Profile` rows count: the app merges them before the engine starts). Measure 5,000 tasks with
     labels and Groups; give the time.
   - `apply(_:)`: one transaction. Each write only if the row still equals `expected` (`SyncRecord.comparable`;
     nil: the row must not exist); a stale key is returned and nothing is written for it. Insert a row with the
     given `id` and fields, or update the row's fields that differ (leave equal ones untouched, so SwiftData sees
     no change), in the order `SyncSchema.types` gives and a task after its parent; a reference to an item that is
     not there is written as none; deletions last (`context.delete`; the model's own cascade takes a task's
     sub-tasks). One `save()`; if it throws, roll back and throw: all or nothing.
   - **The person's edit is never lost.** Tests, on an in-memory container with the main context as the app's views
     use it: (a) an edit saved on the main context between the brain's read and its write comes back as stale and
     is intact; (b) an edit made on the main context and **not yet saved** when the store applies a change to the
     same row: after both have saved, the field the person changed has the person's value and the other fields
     have the engine's (find out what SwiftData's contexts do here and say so; if the person's change can be lost,
     that is the most important line of your report); (c) the main context sees a row the store inserted, changed
     or deleted without being told (a fetch after it, and a `@Query`-style observation if you can test one).
   - `DayAnchoring`'s hook runs inside every save on the app's container, yours too: a date-only `dueDate` written
     un-anchored comes back anchored on the next read. Test that it is stable (applying the anchored record again
     writes nothing) and say what you saw.
3. **`SyncLedgerStore`** (`SyncLedger`): a small store of its own beside the data, never synced and not part of
   `HITListSchema`: its own SwiftData models in their own `ModelContainer` with `cloudKitDatabase: .none`, at
   `<App Group>/<store name without .store>.ledger` (so a side store has its own ledger; in memory for tests and
   for an in-memory app store). `write` is one transaction (all or nothing: test it with a write that fails half
   way). `reset()` removes every row of the ledger's own store (COMMON's "never delete as a reset" is about the
   person's data; this is the engine's scratch memory, and the design depends on its being disposable: say so in
   the code). `saveTransportState` is durable when it returns. Entries: 5,000 written and read back; give the times.
   A ledger file that cannot be opened: the file is moved aside (never deleted) and an empty ledger is used, with
   a line for the log, because an empty ledger is always safe (`dev/SYNC-ENGINE.md` section 7).
4. **`SyncSaveHints`**: from a `ModelContext.didSave` notification to the keys the brain should look at
   (`Set<SyncKey>?`): the inserted and updated rows of the six models as keys; nil (look at everything) when
   anything was deleted (a deleted row can no longer say its `id`) or when in doubt; nothing at all for a save that
   touched none of the six models or came from another container (TipKit keeps a SwiftData store in the same
   process and posts the same notification: DATA-LAYER section 0, point 12). The notification's keys are as
   observed in `SDK-SwiftData-History.md`.

## Done when
The Mac tests pass (counts before and after, your classes named), your own classes pass once on a simulator of
your own (`HITList-141`, deleted at the end), and the report says: what SwiftData does with an unsaved edit on the
main context (item 2b), the times you measured, every choice the brief left you, and what wave 2 needs to know to
wire these into the app.
