# Brief 140: a pretend iCloud, and the simulation's rig (session `sync-fake-cloud`, effort xhigh)

HITList is getting its own sync engine (George: "I want it to be professionally built"). Apple ships no test
double for CloudKit, and a sync engine that has only ever met a working network is not tested. You build the
pretend iCloud the engine is proven on: in memory, exact about the rules the real one keeps, with every failure on
a switch, and the rig that runs several devices against it and checks what must always be true.

**Clock** (Eastern, `TZ=America/New_York date`): a note to the supervisor at 04:30 saying where you are and any
question; report by 05:15.

## Read first
`dev/briefs/COMMON.md` (the Round 28 block), `dev/briefs/ROUND-28.md`, **`dev/SYNC-ENGINE.md`** (all of it;
sections 6 and 9 are yours), every file in `HITListCore/Sources/HITListCore/Sync/` (the contract: `SyncTransport`
is what you implement, exactly as it is), and in the notes folder **`round-28/SDK-CKSyncEngine.md`** (all of it:
your fake must behave as the real engine is documented to, section by section; where the SDK is silent, the rules
T1 to T14 decide, and you say so).

## Yours
New files only: `HITListCore/Sources/HITListCore/Sync/Testing/FakeCloud.swift`, `FakeTransport.swift`,
`SyncSimulation.swift`, `SyncInvariants.swift`; tests in `HITListCore/Tests/HITListCoreTests/Sync/`:
`FakeCloudTests.swift`, `SyncInvariantsTests.swift`.

Not yours: the contract files (a flaw: the diff in your notes folder and a message to the supervisor at once),
`RecordMerge.swift` (session 138), `SyncCore` and anything of the brain's (session 139 builds it now, to the same
rules; in wave 2 it is plugged into your rig, so the rig takes the brain as a parameter), anything in the app.

## What to build
1. **`FakeCloud`** (an actor): one zone of records as iCloud would hold them. Each record: its fields (every key it
   was ever sent, known to `SyncSchema` or not), a version that changes on every accepted save (the `system` token
   a device gets back encodes key and version and nothing a device could use to cheat), and its place in a log of
   changes so a bookmark means "everything after this". Removals for good are in the log too. Accounts: several,
   each with its own zone, so a device can sign out and into another. The zone can be absent, made, deleted,
   purged, or lost to a reset of encrypted data. It can be read directly by a test (`records()`, `record(_:)`) and
   written directly as "another build" would (`poke`: a key no schema lists, to prove T4's "neither sent nor
   cleared").
2. **`FakeTransport`** (`SyncTransport`, one per device, on a `FakeCloud` and a `SyncTransportState`): the bookmark
   and the pending list kept through `SyncTransportState`, so a device "relaunched" (a new `FakeTransport` on the
   same state) carries on where it was, and one whose state was lost starts from nothing. **T1 to T14, each
   exactly**, each with a test named after it in `FakeCloudTests` that drives the transport by hand with a
   recording delegate. In particular: events strictly one at a time; `fetch()` and `send()` return only when their
   events were handled, and a call made from inside `handle` is a programming error you make loud (a precondition
   with a clear message), because the real engine deadlocks there; a save sends every field of the type and
   empties the absent ones, and leaves unknown keys alone; a conflict writes nothing and carries iCloud's version;
   a batch is not all-or-nothing; the pending list's order and its save/delete replacement.
3. **Switches for everything that goes wrong**, per transport or per cloud, deterministic from a seed: the network
   down (T5: `fetch`/`send` throw, the list is kept); the next send refused with `quotaExceeded`, `tooLarge` or
   `rejected` for a chosen key; a batch size (default 250, tests use 2 or 3); a fetch delivered in several events
   and in shuffled order (a task before its Group); the echo of a device's own saves on its next fetch (on by
   default: the real engine's behaviour here is not documented, so the brain must not care); the last event
   delivered a second time; the bookmark lost; **a crash**: `handle` is given the event and the process "dies"
   before the bookmark moves (the same event arrives again after a relaunch), or after `sent` was computed and
   before it was delivered (iCloud holds the save, the device does not know); the zone purged, deleted or reset
   while a device is away; the account signed out, signed in, switched, while running and while not.
4. **The rig** (`SyncSimulation`): a `SimDevice` holds a `MemoryLocalStore`, a `MemoryLedger`, a `FakeTransport`
   and a brain made by a closure the caller gives (`protocol SimBrain: Sendable` with the four things the rig
   needs: start, stop, "the device's items changed", "sync now"; session 139's `SyncCore` will be wrapped to it in
   wave 2, so keep it that small). The rig can: make and relaunch devices (with or without their ledger, with or
   without their transport state); play a script of steps; and play a **seeded random run**: N devices, M steps,
   each step one of: a person's action on a device (make an item of any type with valid references, edit one or
   several fields, complete, move a task to another Group, add or remove a label, make or move a sub-task, delete
   (a task with sub-tasks too), undo a delete (the same key again), rename), a sync on one device, a fault from
   item 3, a relaunch. Then "everyone syncs until quiet" (bounded; not becoming quiet is itself a failure, I7).
   The generator keeps a model of what each device intended so I2 and I3 can be checked.
5. **The invariants** (`SyncInvariants`): I1 to I8 from section 9 as functions over the cloud and the devices that
   return findings in plain words ("device B holds TaskItem/… with title 'x'; iCloud holds 'y'"), plus the seed and
   the step count to replay. Test each on states you build by hand: one that holds and one that breaks it.
6. Until the brain exists you cannot run the rig for real. Prove the rig with a brain of your own in the **tests**
   (not in Sources) that is honest but simple (for example: it sends whatever differs, takes iCloud's record on any
   conflict), and show the invariants catching what that brain gets wrong (it will lose edits: I2 must say so).
   That is the demonstration that the rig finds bugs.

## Rules
- No sleeping, no real time: time is a clock the rig owns and steps. A run of 1,000 steps on 3 devices takes well
  under a second, so wave 2 can run thousands of seeds.
- Everything is `Sendable` and deterministic: the same seed is the same run, on this Mac and on the CI runner
  (Swift 6.3 there; no `#if compiler(>=6.4)`-only API, no unordered iteration deciding an outcome: sort before you
  pick).
- This code ships inside `HITListCore` (under `Sync/Testing/`): no `XCTest` import in Sources, nothing that runs
  unless called.

## Done when
`cd HITListCore && swift test` passes (counts before and after); the report gives the rig's public surface as
wave 2 will call it, each of T1 to T14 with the test that pins it, every place where the SDK was silent and what
you made the fake do, and the output of the demonstration in item 6 (a seed, the finding it produced).
