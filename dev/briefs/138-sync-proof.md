# Brief 138: the merge rules and the contract, proven (session `sync-proof`, effort xhigh)

HITList is getting its own sync engine (George: "I want it to be professionally built"). The supervisor wrote the
contract and the rules by which one record is settled between a device and iCloud. You are the second pair of
eyes: prove them, and where they are wrong, fix them with a test that shows it.

**Clock** (Eastern, `TZ=America/New_York date`): first findings to the supervisor by 04:15; report by 04:50.

## Read first
`dev/briefs/COMMON.md` (the Round 28 block), `dev/briefs/ROUND-28.md`, **`dev/SYNC-ENGINE.md`** (all of it; sections
4, 5 and 7 are yours), then every file in `HITListCore/Sources/HITListCore/Sync/`, `HITList/Models/Models.swift`
(the six models the schema table must match) and, in the notes folder, `round-28/DATA-LAYER.md` sections 1, 3.3,
5 and 6 (what the models hold, which records have fixed ids, how things are deleted and undone).

## Yours
- `HITListCore/Sources/HITListCore/Sync/RecordMerge.swift` (from now on: fix what is wrong, keep its shape and its
  public names: session 139 calls `RecordMerge.merge`, `same` and `normal` while you work).
- New tests: `HITListCore/Tests/HITListCoreTests/Sync/RecordMergeTests.swift`, `RecordMergePropertyTests.swift`,
  `SyncContractTests.swift`.

Not yours: `SyncRecord.swift`, `SyncSchema.swift`, `SyncTransport.swift`, `SyncStorage.swift`, `SyncMemory.swift`
(the supervisor's; three other sessions build on them as they are). A flaw in one of them: write the fix as a diff
in your notes folder and send the supervisor its path at once; do not wait for your report. Nothing in the app.

## Items, in this order (one commit each)
1. **Every rule, by name** (`RecordMergeTests`): M1 to M13 from the table in section 5, each with the cases either
   side of its edge (a tie in `updatedAt`; a deletion one millisecond before and after an edit; `updatedAt` missing;
   a required field missing on iCloud's side; `data` compared by digest and taken as bytes from the side that
   won; a marker with content fields left on it by mistake; a record of a type this build does not know; keys this
   build does not know on either side). `MergeOutcome.rule` says which rule decided: assert it.
2. **The fields' own rules**: `lastWriter`, `clock` (the profile: a name set later on one device and a picture set
   later on the other both survive, with and without a base), `union` (labels added on both sides, removed on
   one, added on one and removed on the other, both emptied).
3. **Properties** (`RecordMergePropertyTests`, a seeded generator of records of every type; print the seed on
   failure, run at least 20,000 cases in under ten seconds):
   - merging twice changes nothing: with the result as the new base and both sides holding it, the result is itself;
   - two devices converge: from one base, device A and device B each change the record at random (edit, delete,
     make again); whichever order they reach iCloud in, once both have settled against what iCloud then holds they
     end with the same record, and so does a third device with no base at all;
   - a field only one side changed keeps that side's value;
   - the result's `updatedAt` is never earlier than either side's;
   - a deletion nobody edited after stays a deletion, on a device with a base and on one without.
   Where a property cannot hold as stated (two devices' clocks; the limits listed under the table), say exactly
   which statement does hold and test that instead. Do not weaken a property to make it pass: a failing property is
   a finding, and the supervisor wants it.
4. **The contract** (`SyncContractTests`): `SyncSchema.types` against the truth. The schema table is hand-written
   from `Models.swift`; from core you cannot see the models, so pin here what can be pinned (every type has
   `updatedAt` and `createdAt`; every reference names a type in the table; the order puts a type after those it
   points at; `known` and `filled` do what they say; a date survives `SyncValue.date` at any sub-millisecond
   value and compares equal after a round trip through milliseconds; `references` sorts and drops repeats; `Codable`
   round trips of every value) and write, in your notes folder, the app-side test that session 141 must carry:
   "every stored property of every model is in the table with the right kind, and nothing is in the table that is
   not on the model" (give them the property list you derived from `Models.swift`, by model).
   `MemoryLocalStore` and `MemoryLedger`: that they behave as `SyncStorage.swift` says (a stale `expected` writes
   nothing and comes back; a reference to nothing is written as none; deleting a task deletes its sub-tasks;
   `write` is all or nothing; `reset` forgets everything).
5. **Read the design against the code** and list every place they disagree, every rule that is missing a case, and
   every case where two rules could both apply. This list is as valuable as the tests.

## Done when
`cd HITListCore && swift test` passes with your tests in it (give the counts before and after), each fix to
`RecordMerge.swift` has a test that failed before it, and your report lists: what you proved, what you changed and
why, what you could not prove, and the disagreements of item 5.
