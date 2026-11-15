# HITList's own sync engine

George, 2026-11-15, after round 27's bolt: "If we need to make our own engine for proper cloud sync, let's get
started. I want it to be professionally built." This is the design every part is built against. The contract in code
is `HITListCore/Sources/HITListCore/Sync/` (`SyncRecord`, `SyncSchema`, `SyncTransport`, `SyncStorage`, `SyncMemory`,
`RecordMerge`); where this page and that code disagree, say so to the supervisor instead of picking one.

## 1. Why, and what changes

Today SwiftData's CloudKit mirror (Core Data's `NSPersistentCloudKitContainer`) syncs the store. It keeps to itself
the one thing an honest bolt needs: the list of what is waiting to go. It names iCloud's records itself, so two
records can carry one `id`. It says "succeeded" for an export that sent nothing. Rounds 20 to 27 built instruments
round it (a comparison of every record, a gate, a second gate) to guess what it knows.

The engine replaces the mirror with parts HITList owns:

- **The records are ours**: one zone, `HITList`, in the private database of `iCloud.com.trammells.hitlist`; one
  record per item, named by the item's `id`; fields under the models' own names. The same item on two devices is
  the same record, always.
- **The list of what is waiting is ours**: so "everything is in iCloud" is a fact the app holds, and the bolt says it.
- **The rules for two devices changing one thing are ours**, written down (section 5) and tested on a pretend iCloud
  with several devices, thousands of random edits and every failure injected (section 9).
- **Apple still does what Apple does best**: `CKSyncEngine` schedules sends and fetches, retries after the network
  or iCloud's limits, and wakes the app on a push. It is the transport, behind a protocol.

Nothing a person has is at risk from the engine's own memory: it can be deleted at any time and the engine merges
everything afresh (section 7). The mirror's zone (`com.apple.coredata.cloudkit.zone`) is never touched by the
engine: it stays as it was at the moment a device moved over.

## 2. The parts

```
 SwiftData store (HITList.store)          HITList's zone in iCloud
        │  items as records                        │
 ┌──────┴────────┐   ┌───────────────┐   ┌─────────┴─────────┐
 │ SyncLocalStore │──▶│   SyncCore    │◀──│   SyncTransport   │
 │ (SwiftData)    │◀──│  (the brain)  │──▶│ (CKSyncEngine, or │
 └───────────────┘   │               │   │  FakeCloud)       │
 ┌───────────────┐   │  RecordMerge  │   └───────────────────┘
 │  SyncLedger    │◀─▶│  SyncSchema   │
 │ (its memory)   │   └───────┬───────┘
 └───────────────┘           │ SyncStatus → the bolt, Settings → iCloud
```

| Part | Where | What |
|---|---|---|
| `SyncSchema`, `SyncRecord`, `SyncValue` | core | What is synced, field by field; the record every part speaks |
| `RecordMerge` | core | How one record is settled (section 5). Pure |
| `SyncCore` | core | The brain: finds what changed here, settles what arrives, keeps the ledger, says the status |
| `SyncTransport` | core (protocol) | The road to iCloud (section 6) |
| `FakeCloud` | core | A pretend iCloud in memory that keeps the transport's rules, for tests with many devices |
| `MemoryLocalStore`, `MemoryLedger` | core | The device's side in memory, for tests |
| `SwiftDataSyncStore` | app | The six models as records, and records written back (`SyncLocalStore`). Reads on contexts of its own, off the main actor; **writes through the app's main context**: SwiftData's main context does not take in a save made by another context, and the person's next save of a row it held would write its old copy back over the engine's (found by session 141) |
| `SyncLedgerStore` | app | The engine's memory on disk, a small store of its own (`SyncLedger`) |
| `CloudKitTransport` | app | `SyncTransport` on `CKSyncEngine`; `CKRecord` ↔ `SyncRecord` |
| `SyncEngine` (wave 2) | app | Wires the parts, the app's life cycle, the switch from the mirror, the bolt |

`HITListCore` knows neither SwiftData nor CloudKit: the brain and its rules are tested by `swift test` in seconds.

## 3. What iCloud holds

- **Zone** `HITList` (`SyncSchema.zoneName`). The transport makes it when it first has something to send and it is
  missing. Fetches are scoped to it.
- **Kept out of the mirror's reach** (found by session 142 on CloudKit Development): the mirror does not keep to its
  own zone. It imports every zone of its container's private database and makes an item out of any record whose
  type is a model's name: it turned the engine's `Project` record into an empty Group, wrote `CD_` fields back
  onto it, and deleted the engine's profile record as a duplicate. So (a) in CloudKit a record's type is never a
  model's name: it is `HL` + the type (`HLTaskItem`, `HLProject`, `HLProfile`, `HLMeta`), a name the mirror
  cannot map; and (b) the engine is meant to live in **a container of its own**, where no mirror ever looks,
  which is George's to approve (section 12): any older build still on the mirror, in anyone's hands, reads the
  mirror's container for as long as it runs.
- **One record per item**, type = the model's name (`TaskItem`, `Project`, `TaskLabel`, `SavedFilter`,
  `Switchboard`, `Profile`), keyed by the item's `id` as `UUID.uuidString` prints it (`SyncKey`). `Profile` is one
  per account: its key's name is `profile` whatever `id` a device's row has. In CloudKit the record's name is
  `<type>.<name>` (`TaskItem.6B1F3E2A-…`, `Profile.profile`, `Meta.meta`): a pending change names a record by its
  name alone, and the name must say the type. (Its CloudKit record type is `HL` + the type, see below.)
- **Fields** are the model's stored properties under their own names (`SyncSchema.types` is the table). A
  relationship is the other record's name (`project`, `parent`, `switchboard`: a string; `labels`: a list of
  strings); none is a CloudKit reference, so iCloud never deletes or refuses anything on its own account. Dates are
  whole milliseconds. `Profile.avatarData` is an asset.
- **A deleted item leaves a marker**: its record stays, with `deletedAt` (when) and `updatedAt`, and every other
  field emptied. A device that was away, or one that merges without a memory, learns of the deletion from it
  instead of sending the item back. A marker older than `SyncSchema.markerLifetime` (400 days) is removed for good
  by whichever device notices.
- **`Meta/meta`** holds `formatVersion`. A build that finds a higher one than it knows stops syncing and says
  "update HITList to sync".
- **Additive forever** (the promise `SchemaVersions.swift` made for the mirror holds for the engine): never rename
  or remove a type or field, never change a kind. A build never sends and never clears a key it does not know, so
  an older build's edit leaves a newer build's fields alone.

## 4. The engine's memory, and how a change is found

The ledger (`SyncLedger`) holds, for every record: **`base`**, the record as iCloud held it when this device and
iCloud last agreed (known fields, data as digests; a marker when they agreed it was deleted); **`system`**, iCloud's
token for that version; **`deletedHereAt`**, when this device noticed the item was deleted here. Plus fetched
records set aside (section 8) and a few facts (`LedgerFact`).

**Nothing is journalled.** The engine never depends on being told that something changed. It compares:

- an item here with no `base`, or whose record differs from `base` (`RecordMerge.same`): **waiting to go**;
- a `base` that is alive with no item here: **deleted here**, `deletedHereAt` is set to now, its marker is waiting
  to go;
- an item that is here again while `deletedHereAt` is set (an undo before the marker went): `deletedHereAt` is
  cleared, and set afresh if the item is deleted again;
- an item here whose `base` is a marker: **made again here** (an undo), waiting to go;
- a marker `base` past its lifetime: waiting to be removed for good.

`SyncCore.reconcile` does that for every record (at start, on return to the app, after a fetch) or for the keys a
save touched (the app passes them on `ModelContext.didSave`; a hint, never the truth). The transport's pending
list is made to match. Whatever writes the store (a view, an intent, an import, the day anchoring, a restore of a
backup) and whether or not `updatedAt` moved, the change is found, because the records differ. A crash between any
two steps leaves a state the same comparison reads correctly.

**The count of what is waiting is exact**, and so is the bolt (section 10).

## 5. How a record is settled (`RecordMerge`)

Inputs: `base` B, the item here L (or none), `deletedHereAt` D (now, if nobody noticed yet), iCloud's record S (alive,
a marker, or none). "Same" means equal on the fields this build knows, required fields filled in, data by digest.
The result is what both sides should end with: the item, a marker, or nothing.

| | Situation | Result |
|---|---|---|
| M1 | Nothing here, nothing there | Nothing |
| M2 | Here, no B, not there | L (new: it goes to iCloud) |
| M3 | Not here, no B, alive there | S (new: it arrives) |
| M4 | Not here, no B, a marker there | S (nothing to delete) |
| M5 | Here and alive there, no B | Same: S. Else the record changed last, whole (`updatedAt`; a tie goes to S); a field with a clock of its own goes by its clock |
| M6 | Here, no B, a marker there | L if `L.updatedAt` is after the deletion (it comes back there), else the marker (it goes here) |
| M7 | Here and alive there, B alive | Field by field: changed on one side only since B: that side's. Changed on both: `lastWriter` → the record changed last (tie: S); `clock(c)` → the later clock (tie: S); `union` → S plus what L added less what L removed. `updatedAt` and clocks: the later |
| M8 | Deleted here, B alive, alive there | S same as B: a marker at D. S changed after D: S (it comes back here). S changed before D: a marker at D |
| M9 | Here, B alive, a marker there | L same as B: the marker (it goes here). L changed after the deletion: L (it comes back there). Else the marker |
| M10 | Not here, a marker there | B alive (deleted here too): a marker at the later of D and S's deletion, so the time does not depend on who reached iCloud first; it is sent if it differs from S. B a marker: S, unless this device still has a later marker of its own to send (`deletedHereAt` set, never "now"): then that one |
| M11 | B present, not there at all | L same as B, or not here: nothing. L changed: L, new again |
| M12 | Here, B a marker | S the marker this device knew (the same time as B's): L, it was made again here, whatever its dates (an undo, an import). S a newer marker (deleted again elsewhere since): as M6. Alive there too: as M5 |
| M13 | Not here, B a marker, alive there | S: it was made again elsewhere. Unless this device still has a later deletion of its own to send (`deletedHereAt` set, never "now"): then as M8 against that time (S if S changed after it, else a marker at it) |

Then: the device is written if it differs from the result (through `LocalWrite.expected`: if the person changed the
item meanwhile, nothing is written and it is settled again); `base` becomes S; and if the result differs from S it
is waiting to go.

A marker is read as its key and its time and nothing else, and a set of references as a set (sorted, no repeats,
an empty one the same as none), whatever a transport hands over. A type this build does not know never reaches
the merge: the brain leaves such records alone (section 8).

Known limits, on purpose: clocks are the devices' own (a device with a wrong clock can win or lose a contest it
should not); two devices that both change the same field of the same item while apart keep one of the two values;
when their `updatedAt` are equal the one that reached iCloud first stands (every device still ends with the same
record); `flipCount` is last-writer like any field (two devices flipping the same switch apart count once); an item
deleted on a device before that device and iCloud ever agreed on it leaves no marker (another device's copy of it
arrives as new: the seeded filters, the `flipboard` label and the profile have fixed keys, so this can be seen with
them); an undo is ordered against a deletion elsewhere by the item's `updatedAt`, so the app moves `updatedAt` when
it puts a deleted item back.

## 6. The transport's rules

`SyncTransport` is implemented twice: on `CKSyncEngine`, and by `FakeCloud`. Both keep these, so a test on the fake
means the same on CloudKit. `SyncCore` relies on nothing else.

- **T1 Serial.** Events come one at a time; the next waits until `handle` returns. Whatever an event brought must be
  on disk before `handle` returns: the transport then moves its bookmark and will not bring it again. `handle`
  never calls `fetch()` or `send()`.
- **T2 Fetch.** A fetch brings every record changed since the bookmark as iCloud holds it now (only the latest
  version), in no particular order (a record may come before one it points at), over one or more `fetched` events,
  and the keys of records removed for good. Without a bookmark: every record in the zone. It may bring again what
  this device itself just sent (an echo), and after a lost bookmark everything: handling is idempotent.
- **T3 Pending.** The list is ordered, holds a key once (a save and a delete of one key replace each other, the last
  added stays), and survives a relaunch. The record is asked for when its turn comes (`recordToSend`); nil drops
  the change.
- **T4 A save accepted.** Every field of the record's type (`SyncSchema`) is written: one present with its value, one
  absent emptied; `deletedAt` likewise. A key the type does not list is neither sent nor cleared. `saved` carries
  the record as iCloud now holds it and its new token. The change leaves the list **before** `sent` is delivered
  (as an answered change does under T6, T7 and T9), so a change the brain adds back while it handles `sent` (the
  person changed the item again while the save was on its way) stays on the list.
- **T5 Passing trouble** (no network, iCloud busy or limiting, the account briefly unavailable): the change stays on
  the list and the transport tries again by itself. `didSend(error:)` / `didFetch(error:)` carry the words.
- **T6 Conflict.** A save whose `system` is not the token of iCloud's current version (or that has none while iCloud
  holds the record) is refused whole. The failure carries iCloud's version. The change leaves the list; the brain
  settles and adds it again if something is still to go.
- **T7 Unknown.** A save with a token for a record iCloud no longer holds is refused (`unknownItem`) and leaves the
  list. A delete of a record iCloud does not hold counts as done.
- **T8 Removed for good.** `delete` removes the record; other devices learn of it at their next fetch (`removed`).
- **T9 Refused for good** (`quotaExceeded`, `tooLarge`, `rejected`): the change leaves the list; the brain decides.
- **T10 Batches.** A send may take several batches (250 records at most each on CloudKit), one `sent` event each.
  A batch is not all-or-nothing.
- **T11 The zone lost.** `zoneLost(reason)`, during a fetch or when a send finds the zone missing. By then the
  transport has forgotten its bookmark and its list.
- **T12 The account.** `account(change)` when the signed-in account is not the one the transport's state belongs to:
  the first event of the first sync after `start` if it changed while the app was not running (never inside
  `start` itself), or when it happens. The transport has forgotten its bookmark and its list by then. With no
  account nothing is fetched or sent. A transport that lost its own state announces `signedIn` for the account that
  is signed in, even when that is the account the ledger belongs to: the brain reads a sign-in to its own account
  as no change of account (only the bookmark and the list are gone, as after T13).
- **T13 Reset.** `reset()` forgets the bookmark and the list; the next fetch brings every record.
- **T14 Now.** `fetch()` and `send()` return when their events have been handled and throw when they could not run.
  The transport may also sync by itself at any time (a push, its schedule): the same events arrive.

## 7. A merge without a memory

With an empty ledger (a first sync, a device moving over from the mirror, a reset, a lost ledger file) every item
here has no `base`. Nothing is sent before the first whole fetch has finished (`LedgerFact.firstFetchDone`), so the
device first learns what iCloud holds; each record is then settled by M2 to M6: the same item on both sides becomes
one record, an item deleted elsewhere is found deleted by its marker, and only what iCloud truly lacks is sent.
This one path is the migration, the repair, and the answer to "what if the engine's own file is damaged".

## 8. What arrives

- Records are settled in `SyncSchema.types` order, a task after its parent. A record that points at an item which
  is neither here nor in the same batch is **set aside** in the ledger (`deferUpsert`) until the fetch ends; then
  what is still missing is written as no reference, and because that differs from S, iCloud's dangling reference
  is cleared on the next send.
- A type this build does not know is ignored and nothing is kept for it.
- `Meta/meta` with a `formatVersion` above `SyncSchema.formatVersion`: the engine holds (`needsUpdate`).
- After a fetch that wrote anything the app runs what the mirror's import used to trigger (the name deduplication,
  reminders, widgets, Spotlight). The day anchoring runs inside the save itself and is canonical (a day is 10:00
  UTC on every device), so what it rewrites is the same everywhere and settles in one more send at most.

## 9. How it is proven

1. `swift test`: `RecordMerge` rule by rule and by property (the result is the same whatever order two devices
   learn of things; merging twice changes nothing); `SyncCore` on scripted transports, every rule T1 to T14 and every
   failure; the ledger written before the bookmark moves.
2. **Simulation** on `FakeCloud`: several devices, thousands of random edits, deletions, undos and sub-task moves,
   with the network dropping, conflicts, crashes between any two steps (the device's process thrown away and made
   again from its store and ledger), echoes and lost bookmarks. After everyone has synced:
   - **I1 Same everywhere**: every device holds the same items with the same fields, and iCloud holds exactly those.
   - **I2 No lost edit**: a field one device changed and no other did has that value everywhere.
   - **I3 Nothing comes back**: an item deleted on one device and not changed elsewhere afterwards is gone
     everywhere, on a device that merges without a memory too.
   - **I4 Twice is once**: any event delivered twice, any crash, changes nothing in the end.
   - **I5 One of each**: never two items with one key.
   - **I6 Whole**: no item points at one that is not there.
   - **I7 Quiet**: when nothing is waiting, another sync sends nothing. No ping-pong.
   - **I8 A newer build's fields survive** an older build's edit.
3. The app's parts against an in-memory SwiftData store (every field of every model there and back; an edit made
   while the engine writes is not lost).
4. End to end on CloudKit **Development**: two Debug Mac apps on two side stores, as two devices.
5. The move from the mirror rehearsed on copies of a real store before any real device moves.

## 10. Holds and the bolt

The engine is in one state (`SyncStatus`): off, starting, idle, fetching, sending, or **held** for a reason only the
person or the world can lift:

| Hold | When | What the engine does |
|---|---|---|
| `noAccount` | Signed out of iCloud | Nothing is sent or fetched. Parity with the mirror: what was synced leaves the device at sign-out, after a backup is written; it returns at sign-in |
| `needsUpdate` | iCloud's format is newer | Nothing is sent or fetched |
| `zonePurged` | The person removed HITList's data in iCloud's settings | Nothing is deleted here by itself. The person is asked: remove here too, or keep and send again |
| `storageFull` | iCloud is full | What is waiting stays waiting; tried again on return to the app |
| `duplicates` | Two rows share an `id` | The app merges them, then the engine starts |
| `massDeletion` | A compare finds nothing on the device at all, or more than 50 items gone that are also more than half of what iCloud holds | Nothing is sent and nothing is marked deleted: a store that reads empty by mistake (the app falls back to an empty store when its file will not open) must never empty every device. It lifts by itself when the items are there again, or when the person says they did delete them (found by session 139) |
| `failed` | The store or the ledger could not be read or written | Tried again at the next start; the words are shown |

A zone lost by reset of encrypted data, or deleted in testing: the ledger is forgotten and everything here is sent
again. An account switched: as sign-out, then sign-in.

**The bolt** is filled exactly when: idle, nothing waiting, the first fetch finished, no error. Hollow with the
number when changes are waiting ("3 changes waiting to go to iCloud"). No comparison of every record, no gates, no
guessing; Check iCloud… stays as the person's own audit.

## 11. Moving from the mirror

- `Preferences` holds which engine a device uses; **every released build until George says otherwise uses the
  mirror**, as today. The engine's code ships dark.
- Moving a device: the app backs up, merges rows that share an `id`, reopens the same store file without the mirror
  (`cloudKitDatabase: .none`, the store itself is untouched), and the engine starts with an empty ledger
  (section 7). The first device sends everything; each later one finds its items already there.
- Devices still on the mirror and devices on the engine do not see each other's changes until they have all moved:
  they move together, George's first. (That is only true because the engine's records are out of the mirror's
  reach, section 3: in the mirror's own container, under model names, a mirror would import them as empty items.)
- Going back: the mirror's zone still holds everything as of the move.
- iCloud's Production schema gains the new record types before any released build runs the engine (additive;
  George's click, as for every schema change).

## 12. Decisions that are George's (each can be changed before Production holds a record)

0. **A container of its own for the engine** (`iCloud.com.trammells.hitlist.sync`, a third beside the tasks' and
   Shared Tasks'). The mirror reads every zone of its own container (section 3), and builds on the mirror will be
   in friends' hands for as long as they do not update. A separate container is the one arrangement in which
   nothing an old build does can touch the engine's records. It is registered once (automatic signing does it, as
   it did for Shared Tasks' container) and cannot be removed afterwards, which is why it waits for his word. Until
   then everything runs in the tasks' container on Development only, under the `HL` record types, with the mirror
   off on the stores that use the engine.
1. **Plain or encrypted fields.** As built, fields are stored as the mirror stores them today (protected by the
   account, readable in the CloudKit dashboard for support). `SyncSchema` can mark fields end-to-end encrypted
   instead (titles, notes, names); the cost is a dashboard that shows nothing and one more way for a recovery to
   lose data. Changing it later means a new format version.
2. **Sign-out removes what was synced from the device** (as the mirror does), after a backup.
3. **A purge in iCloud's settings asks** instead of deleting the device's copy (Apple's guidance is to delete).
4. **When devices move**: his first, then friends.
