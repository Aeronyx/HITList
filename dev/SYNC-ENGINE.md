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

- **The records are ours**: one zone, `HITList`, in the private database of a container of the engine's own,
  `iCloud.com.trammells.hitlist.sync` (round 30; section 3 says why); one record per item, named by the item's
  `id`; fields under the models' own names. The same item on two devices is the same record, always.
- **The list of what is waiting is ours**: so "everything is in iCloud" is a fact the app holds, and the bolt says it.
- **The rules for two devices changing one thing are ours**, written down (section 5) and tested on a pretend iCloud
  with several devices, thousands of random edits and every failure injected (section 9).
- **Apple's `CKSyncEngine` is the road to iCloud**, behind a protocol: it batches, keeps the bookmark and the
  pending list, and speaks CloudKit. It runs **with its own scheduling off** (round 32, section 6a): left to
  schedule itself it fetched only when a push told it to, and missed what changed while the app was closed. HITList
  asks for each sync itself: at launch, on coming forward, on a push, and after a change.

Nothing a person has is at risk from the engine's own memory: it can be lost at any time and the engine merges
everything afresh (section 7). One thing only lives nowhere else: a deletion made on this device that has not yet
gone to iCloud. A memory lost in that moment brings the item back (it is never lost the other way), so the app
does not throw the memory away lightly: a row of it that cannot be read is forgotten alone, and the brain carries
unsent deletions across every forgetting it does itself. The mirror's zone (`com.apple.coredata.cloudkit.zone`, in
the tasks' container) is never touched by the engine, which never opens that container: it stays as it was at the
moment a device moved over.

**The engine deletes in iCloud only what was deleted** (round 29, the review). A deletion is known when the store
wrote it down as it was saved, and in no other way; an item that is merely not on a device is missing and comes
back from iCloud (section 4, M14). A store that reads empty, loses rows or is put back from an older copy cannot
delete anything for anyone, and the engine never has to ask a person whether they meant it.

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
| `SyncDeletionLog`, `SyncSaveHintObserver` | app | Every save watched: the rows it is about to delete taken down in the ledger's file before it commits (`willSave`, where a row can still say its `id`), and after it the keys it touched handed to the brain |
| `CloudKitTransport` | app | `SyncTransport` on `CKSyncEngine`; `CKRecord` ↔ `SyncRecord` |
| `SyncEngine` (wave 2) | app | Wires the parts, the app's life cycle, the switch from the mirror, the bolt |

`HITListCore` knows neither SwiftData nor CloudKit: the brain and its rules are tested by `swift test` in seconds.

## 3. What iCloud holds

- **Container** `iCloud.com.trammells.hitlist.sync` (`SyncEngineSwitch.containerID`), the engine's own, a third
  beside the tasks' (`iCloud.com.trammells.hitlist`, the mirror's) and Shared Tasks'. George, 2026-11-16: "continue
  freely on the separate container for the iCloud engine if you think that's the best approach for a professional
  and robust (yet not overengineered) iCloud sync setup." It was registered that day (automatic signing did it at
  the first build that listed it; a container cannot be removed afterwards). Both apps' entitlements list it, the
  tasks' first.
- **Its schema is a file in the repository**, `dev/cloudkit/sync-engine.ckdb` (round 32), pinned to `SyncSchema` by
  `SyncEngineSchemaFileTests`: the `HL` record types, every field, and one index (`recordName` queryable, so the
  CloudKit Console can list records; the engine never queries). Production gets exactly the file, in three steps
  `scripts/release.sh` prints when Production lacks any of it: `xcrun cktool reset-schema` for the container's
  Development side (test records only), `xcrun cktool import-schema --file dev/cloudkit/sync-engine.ckdb`, then
  Deploy Schema Changes in the console. Never deployed from whatever Development happens to hold: the transport's
  probe writes a field of its own there on purpose (`probeNewerBuildField`), so after a probe run Development is
  reset and the file imported again before any deploy. `release.sh` does not compare this container's two
  environments; it checks Production against the file.
- **Zone** `HITList` (`SyncSchema.zoneName`). The transport makes it when it first has something to send and it is
  missing. Fetches are scoped to it.
- **Kept out of the mirror's reach** (found by session 142 on CloudKit Development): the mirror does not keep to its
  own zone. It imports every zone of its container's private database and makes an item out of any record whose
  type is a model's name: it turned the engine's `Project` record into an empty Group, wrote `CD_` fields back
  onto it, and deleted the engine's profile record as a duplicate. Two locks follow. (a) **The container of its
  own**: no build on the mirror, in anyone's hands for however long, ever looks there, so nothing an old build does
  can reach the engine's records; an engine's save pushes nothing to a mirror; the mirror's zone stays exactly as it
  was at the move (the way back); and each container's schema is deployed on its own. It costs an identifier in the
  entitlements and no code. (b) In CloudKit a record's type is never a model's name: it is `HL` + the type
  (`HLTaskItem`, `HLProject`, `HLProfile`, `HLMeta`), a name the mirror cannot map. With (a) in place (b) is not
  needed; it stays because it costs a prefix and would hold if a mirror were ever pointed at this container by
  mistake.
- **A new container takes a few minutes to be known to a device.** In the first minutes after it was registered a
  send answered "Not Authenticated: could not determine iCloud account status" and then "Bad Container: couldn't
  get container configuration from the server", while `cktool` already exported its schema; the third run, about
  five minutes on, passed. Nothing to fix: it happens once per container, before any tester exists.
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

**A change is found by comparing.** The engine never depends on being told that something was made or changed:

- an item here with no `base`, or whose record differs from `base` (`RecordMerge.same`): **waiting to go**;
- an item here whose `base` is a marker: **made again here** (an undo), waiting to go;
- a marker `base` past its lifetime: waiting to be removed for good.

**A deletion is never found by comparing** (round 29; the first engine did, and needed a guard of numbers, a
question to the person and a vouch from the app to live with it). It is known only when the store wrote it down as
it happened (`SyncLocalStore.deletions`): the app watches every save and takes down the key of each row about to be
deleted, and of a task's sub-tasks that go with it, before the save commits, in the ledger's own file. The brain
notes them (`deletedHereAt`) before it compares or settles anything, held or not:

- a deletion written down, `base` alive: **deleted here**, its marker is waiting to go;
- a deletion written down, no `base` (never agreed with iCloud, or before the first fetch): kept until a fetch
  shows whether iCloud holds the item (M3 against the deletion), then dropped;
- an item that is here again while `deletedHereAt` is set (an undo before the marker went): cleared;
- **an item iCloud holds that is not here and has no deletion written down: missing.** Its entry is forgotten and
  every record is asked for again, so iCloud's comes back (M14). Nothing is deleted in iCloud, nobody is asked.

The engine's own deletions (a marker that arrived, a sign-out) are never written down as a person's. The notes
live and die with the ledger: one made for another store file can never delete anything.

`SyncCore` compares every record at a start and when the app comes forward (a change whose hint was missed is found
there), and otherwise the keys a save touched (`localChanged`: the rows it made, changed or deleted, by name). The
transport's pending list is made to match. Whatever writes the store (a view, an intent, an import, the day
anchoring) and whether or not `updatedAt` moved, a change is found, because the records differ. A crash between any
two steps leaves a state the same comparison reads correctly.

**The count of what is waiting is exact**, and so is the bolt (section 10).

## 5. How a record is settled (`RecordMerge`)

Inputs: `base` B, the item here L (or none), `deletedHereAt` D (when a deletion here was written down; nothing stands
in for it), iCloud's record S (alive, a marker, or none). "Same" means equal on the fields this build knows, required fields filled in, data by digest.
The result is what both sides should end with: the item, a marker, or nothing.

| | Situation | Result |
|---|---|---|
| M1 | Nothing here, nothing there | Nothing |
| M2 | Here, no B, not there | L (new: it goes to iCloud) |
| M3 | Not here, no B, alive there | S (new: it arrives). Unless this device holds a deletion of its own still to send for it (`deletedHereAt` set, kept across a forgotten ledger, never "now"): then as M8 against that time |
| M4 | Not here, no B, a marker there | S (nothing to delete). With a deletion of this device's own still to send: a marker at the later of the two times |
| M5 | Here and alive there, no B | Same: S. Else the record changed last, whole (`updatedAt`; a tie goes to S); a field with a clock of its own goes by its clock. Unless this device remembers what it last sent for the record and never had an answer (the save was accepted and the reply lost): then what it sent is the base and the two are settled as M7, so an edit here after that send and an edit elsewhere both survive (found by session 145's rig) |
| M6 | Here, no B, a marker there | L if `L.updatedAt` is after the deletion (it comes back there), else the marker (it goes here) |
| M7 | Here and alive there, B alive | (When this device sent the record and never had an answer, the save may have landed: for each field, the value it sent and iCloud holds is taken as agreed, so a field the person has since changed back still counts as changed here; round 29, seed 284.) Field by field: changed on one side only since B: that side's. Changed on both: `lastWriter` → the record changed last (tie: S); `clock(c)` → the later clock (tie: S); `union` → S plus what L added less what L removed. `updatedAt` and clocks: the later |
| M8 | Deleted here (D written down), B alive, alive there | S same as B: a marker at D. S changed after D: S (it comes back here). S changed before D: a marker at D. The marker is never earlier than the version it deletes (the later of D and `S.updatedAt`): a device whose clock runs behind still deletes what it held |
| M9 | Here, B alive, a marker there | L same as B: the marker (it goes here). L changed after the deletion: L (it comes back there). Else the marker |
| M10 | Not here, a marker there | With a deletion here written down: a marker at the later of D and S's deletion, so the time does not depend on who reached iCloud first; it is sent if it differs from S. Without one: S |
| M11 | B present, not there at all | L same as B, or not here: nothing. L changed: L, new again |
| M12 | Here, B a marker | S the marker this device knew (the same time as B's): L, it was made again here, whatever its dates (an undo, an import). S a newer marker (deleted again elsewhere since): as M6. Alive there too: as M5 |
| M13 | Not here, B a marker, alive there | S: it was made again elsewhere. Unless this device still has a later deletion of its own to send: then as M8 against that time (S if S changed after it, else a marker at it) |
| M14 | Not here, B alive, alive there, **no deletion written down** | S: the item is missing here, not deleted, and comes back. Nothing goes to iCloud |

Then: the device is written if it differs from the result (through `LocalWrite.expected`: if the person changed the
item meanwhile, nothing is written and it is settled again); `base` becomes S; and if the result differs from S it
is waiting to go. A fetch that moves a record's base clears a refusal for good of that key: what iCloud refused was
a send against the old version, so it is tried once more against the new one, once per version another device
makes (round 32, brief 160).

A marker is read as its key and its time and nothing else, and a set of references as a set (sorted, no repeats,
an empty one the same as none), whatever a transport hands over. A type this build does not know never reaches
the merge: the brain leaves such records alone (section 8).

A contest between a change and a deletion at the same millisecond goes to the deletion. `D` is when the brain took
note of the deletion the store wrote down (never earlier than the deleted version's own time), before it settles
anything with it, so a marker sent twice is the same marker.

Known limits, on purpose: clocks are the devices' own (a device with a wrong clock can win or lose a contest it
should not); two devices that both change the same field of the same item while apart keep one of the two values;
when their `updatedAt` are equal the one that reached iCloud first stands (every device still ends with the same
record); `flipCount` is last-writer like any field (two devices flipping the same switch apart count once); a deletion made
in the instant before the app is killed, if even its note did not reach the ledger's file, brings the item back
(never the other way); an undo is ordered against a deletion elsewhere by the item's `updatedAt`, so the app moves `updatedAt` when
it puts a deleted item back; a change that does not move `updatedAt` (the day anchoring, a board moving its switches)
is found and sent like any other but is ordered by the old time, so it loses a contest with a deletion or with
another device's change to the same field; two devices that meet for the first time with different labels on the
same task keep one side's (with no base a removal cannot be told from an addition); and once a marker has been
removed for good, after `markerLifetime` (400 days), a device that merges without a memory and still holds the
item sends it back. Two more, each pinned by a `testLimit…` script in the simulation (round 32, brief 150): an item
deleted on one device and then changed on two others (or changed on one and put back on another) before they hear
of each other comes back as the copy changed last, whole, and what the other device changed on it is lost; and
after HITList's data in iCloud is reset or deleted every device sends everything again, and until each has heard
back for an item two devices' copies of it meet as strangers and the one changed last wins whole.

## 6. The transport's rules

`SyncTransport` is implemented twice: on `CKSyncEngine`, and by `FakeCloud`. Both keep these, so a test on the fake
means the same on CloudKit. `SyncCore` relies on nothing else.

- **T1 Serial.** Events come one at a time; the next waits until `handle` returns. Whatever an event brought must be
  on disk before `handle` returns: the transport then moves its bookmark and will not bring it again. `handle`
  never calls `fetch()` or `send()`.
- **T2 Fetch.** A fetch brings every record changed since the bookmark as iCloud holds it now (only the latest
  version), in no particular order (a record may come before one it points at), over one or more `fetched` events,
  and the keys of records removed for good. Without a bookmark: every record in the zone. It may bring again what
  this device itself just sent (an echo), and after a lost bookmark everything: handling is idempotent. A fetch
  that ended without reaching iCloud is told with an error, never as one that ended well: with no bookmark the
  brain takes a fetch that ended well for the whole of what iCloud holds (the review's finding 3). A record of the
  zone the transport cannot read (an asset not downloaded, or over the limit) is never dropped while the bookmark
  moves on: it is owed, kept in the transport's state, asked for again by name at the end of each fetch that
  reached iCloud, and delivered as fetched once it can be read; while one is owed, from the second fetch under a
  state, `didFetch` carries words naming how many and the first (round 32, brief 149). The transport tells the
  owed keys (`owed`) before `didFetch`; the brain does not take that fetch as proof iCloud lacks the key, and keeps
  a deletion of its own with no base for it (brief 160).
- **T3 Pending.** The list is ordered, holds a key once (a save and a delete of one key replace each other, the last
  added stays), and survives a relaunch. The record is asked for when its turn comes (`recordToSend`); nil drops
  the change. `pending`, `add`, `remove` and `reset` never wait for the delegate: the brain calls them from inside
  `handle` too.
- **T4 A save accepted.** Every field of the record's type (`SyncSchema`) is written: one present with its value, one
  absent emptied; `deletedAt` likewise. A key the type does not list is neither sent nor cleared. `saved` carries
  the record as iCloud now holds it and its new token. The change leaves the list **before** `sent` is delivered
  (as an answered change does under T6, T7 and T9), so a change the brain adds back while it handles `sent` (the
  person changed the item again while the save was on its way) stays on the list.
- **T5 Passing trouble** (no network, iCloud busy or limiting, the account briefly unavailable): the change stays on
  the list and is tried again without the person: by the engine's pump in the app (section 6a), by the next
  `send()` in a test. `didSend(error:)` / `didFetch(error:)` carry the words. `internalError`, `assetFileNotFound`
  and `assetFileModified` are passing trouble too.
- **T6 Conflict.** A save whose `system` is not the token of iCloud's current version (or that has none while iCloud
  holds the record) is refused whole. The failure carries iCloud's version. The change leaves the list; the brain
  settles and adds it again if something is still to go. A conflict whose iCloud version cannot be read is not
  told: the change leaves the list and the record is owed (T2); when it arrives the brain settles it, the send
  being one without an answer.
- **T7 Unknown.** A save with a token for a record iCloud no longer holds is refused (`unknownItem`) and leaves the
  list. A delete of a record iCloud does not hold counts as done.
- **T8 Removed for good.** `delete` removes the record; other devices learn of it at their next fetch (`removed`).
- **T9 Refused for good** (`quotaExceeded`, `tooLarge`, `rejected`): the change leaves the list; the brain decides.
  `Meta/meta` honours a refusal like any other record.
- **T9a Not ready** (`notReady`: CKError 12, 15, 10, 5, 8, 32, 18, 24; a Production schema without a record type or
  a field refuses each record with 12): about the build, the environment or the account, never about the record.
  The change leaves the list; the brain holds `iCloudNotReady`; nothing is refused for good (round 32, review 148:
  a schema not yet deployed would have parked a whole store as "refused" until each item was edited).
- **T10 Batches.** A send may take several batches (250 records at most each on CloudKit), one `sent` event each.
  A batch is not all-or-nothing.
- **T11 The zone lost.** `zoneLost(reason)`, during a fetch or when a send finds a zone missing that this device
  knew to exist (one it never knew is simply made). By then the transport has forgotten its bookmark and its list.
- **T12 The account.** The transport writes an account change down as owed before it tells the brain and crosses
  it off when the brain has handled it, so a kill in between tells it again at the next launch (Apple's engine
  announces a change once). `account(change)` when the signed-in account is not the one the transport's state belongs to:
  the first event of the first sync after `start` if it changed while the app was not running (never inside
  `start` itself), or when it happens. The transport has forgotten its bookmark and its list by then. With no
  account nothing is fetched or sent. A transport that lost its own state announces `signedIn` for the account that
  is signed in, even when that is the account the ledger belongs to. The brain reads a sign-in to its own account
  as no change of account (nothing of the person's leaves the device) but as **the transport's memory lost**, and
  forgets its own with it (section 7): a bookmark that starts afresh never tells of a zone lost in the meantime, so
  a ledger kept would hold bases for records iCloud no longer has, and nothing would send them again (found by
  session 140's rig).
- **T13 Reset.** `reset()` forgets the bookmark and the list and nothing else; the next fetch brings every record. The
  account and what the device knew of the zone are kept, and no account event follows from it: a reset is how the
  brain asks for every record again with its memory intact, and must not look like a transport that lost its
  state (T12), which costs the brain its ledger (the review's finding 10). A fetch in flight when it is called
  ends there. An expired change token is answered by the transport itself: the bookmark forgotten, the account, the
  zone, the owed records and the pending list kept, everything fetched once more within that fetch; never a loop.
  The new engine is made before the forgotten state is written, so the old one cannot write its bookmark back
  (round 32, review 148).
- **T14 Now.** `fetch()` and `send()` return when their events have been handled and throw when they could not run.
  The transport may also sync by itself at any time (a push, its schedule): the same events arrive.

## 6a. How the engine is driven (round 32)

**Apple's engine never schedules itself here** (`automaticallySync: false`). Found with George's iPhone beside this
Mac, on CloudKit Development: with the scheduling on, a fetch asked for after a relaunch began and ended without
asking iCloud anything (the trace: `willFetchChanges`, `didFetchChanges`, nothing between), on the Mac in the
background and on the phone in front alike. The engine then fetches only when a push tells it to, so six changes
the phone made while the Mac's app was closed stayed in iCloud, the Mac's bolt filled, until Check iCloud… named
them; CloudKit asked directly, beside the engine, reported the zone as changed. With the scheduling off the same
fetch asks the database what changed and brings it (73 records, the comparison exact). That is also the only mode
the transport's probe ever ran in, so the mode that was proven is now the mode that runs.

What asks for a sync (`SyncEngine`): the launch; the app coming forward (everything compared first); a push (the
app's delegate, `syncWithin`); the person's Sync now and Check iCloud…; and **the pump** (`pumpAfter`): one sleep
to a known deadline, armed by what the brain just said. A new change is sent a second later; a try that left
something waiting, or ended in trouble, is followed by the next after 5 s, 30 s, 2 min, then every 10 min; nothing
waiting and no trouble arms nothing; a hold arms nothing (the person lifts it, or coming forward tries again). T5's
"tries again by itself" is kept by this pump, not by Apple's scheduler.

**The push subscription is the engine's own** (`CloudKitTransport.ensureSubscription`, id `HITListSync-Private`):
saved once per device and account after a fetch that reached iCloud. Apple's engine keeps one of its own only while
it schedules itself. After the Development side was reset in round 32 no push reached either device until one was
saved again; then a change on the Mac reached the phone in seconds ("Sync for a push: done"). The other way was
not seen that night (no push reached this Mac's push daemon at all; in round 31 it did): to be watched in George's
first week, where the sync log's "Sync for a push" lines say.

A manual fetch asks for every zone (`.all`, as Apple's sample does) and `nextFetchChangesOptions` keeps the records
fetched to this store's zone. The sync log has one line per fetch: what it brought and whether it reached the zone.

## 7. A merge without a memory

With an empty ledger (a first sync, a device moving over from the mirror, a reset, a lost ledger file) every item
here has no `base`. Nothing is sent before the first whole fetch has finished (`LedgerFact.firstFetchDone`), so the
device first learns what iCloud holds; each record is then settled by M2 to M6: the same item on both sides becomes
one record, an item deleted elsewhere is found deleted by its marker, and only what iCloud truly lacks is sent.
This one path is the migration, the repair, and the answer to "what if the engine's own file is damaged".

**The ledger never outlives the bookmark, nor the bookmark the ledger.** The transport's state is one of the ledger's
facts, so they are lost together; and when the transport says its state is gone (T12) the brain forgets the ledger.
Two things are carried across: what records wait for (the device's own knowledge, not a memory of iCloud's; round
32), and a deletion this device made and has not yet sent (`deletedHereAt`), kept as an entry
with no base, and settles against iCloud's record like M8 (iCloud's stands if it changed after the deletion, else
the marker goes). Without that, an item deleted here a moment before the memory was lost would come back. (A
ledger file lost whole, or one that belonged to another store file, takes these notes with it: the items come back.)

## 8. What arrives

- Records are settled in `SyncSchema.types` order, a task after its parent.
- **A reference to an item that is not on this device is never cleared by this device.** (The first design wrote a
  fetched record without a reference whose target had not arrived by the end of the fetch, and sent that back:
  session 140's rig showed a label made on one device and sent a batch after its task being wiped from the task
  everywhere. An item that is absent may only be late.) Instead:
  - The brain reasons about a record **as it would be with every reference honoured**: the device's record plus the
    references it is *waiting* for. That whole record is what is compared with `base`, what goes into the merge as L,
    and what `recordToSend` sends. So a reference iCloud holds to an item this device lacks is neither a difference
    nor ever sent away.
  - The device is written with what it can show: the whole record less the references to items that are not here.
    The ledger lists, per record, the references it is waiting for (the `deferred` list: the record's key and those
    reference fields).
  - A record starts waiting for an item whenever its `base` points at an item that is not on the device: a fetched
    record whose target has not arrived, or an item deleted here (the store itself took the reference off the rows
    that pointed at it).
  - When an item that is waited for appears on the device (fetched, or made again here by an undo), the reference is
    written on the device and the record stops waiting for it. So an undo of a deleted label gives its tasks their
    label back, on every device.
  - Only a person's own change to the field is sent: another Group chosen, a label removed while the label exists.
    A to-one reference the device holds a value for is the person's; the waited-for one is honoured only while the
    field is empty.
  - **A reference the person changed is theirs until it has gone** (round 32, brief 150): a to-one the device holds
    with another item than the base names, or emptied while the base's item was here, is the person's; the base's
    reference is marked cleared and not waited for again, so neither a deletion here nor an undo brings it back.
    A name the person took off a set while its item was here likewise (`<field>.removed` in the wait).
  - What is waiting to go is sent with the items pointed at before those that point at them (`SyncSchema.types`
    order, a task after its parent), so iCloud rarely holds a record ahead of its target.
- **A deletion that arrives never takes with it an item made or changed here after it** (found by the review,
  finding 1: a sub-task added or edited under a task after another device deleted that task vanished with it, and
  an older one's marker then deleted it everywhere). Before a task's deletion is written, every sub-task the device
  holds under it is settled as if its own deletion had arrived at the same moment: unchanged here, or last changed
  at or before that moment: it goes, named as a deletion of its own; made here, changed here after it, or moved
  under the task here: it stays, written out from under the task first (its `parent` then waits, as above). And
  the store is strict: it deletes exactly the rows the writes name, and a deletion whose cascade would take a row
  no write names comes back stale and deletes nothing.
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
   - **I2 No lost edit**: a field one device changed and no other did has that value everywhere. A set of
     references is judged name by name (a label the store took off a task because the label was deleted is not
     a person's removal).
   - **I3 Nothing comes back**: an item deleted on one device and not changed elsewhere afterwards is gone
     everywhere, on a device that merges without a memory too. And nothing goes that nobody deleted: an item a
     store lost with no deletion written down is back on that device and deleted nowhere (the rig's `rowsLost`).
   - **I4 Twice is once**: any event delivered twice, any crash, changes nothing in the end.
   - **I5 One of each**: never two items with one key.
   - **I6 Whole**: no item points at one that is not there.
   - **I7 Quiet**: when nothing is waiting, another sync sends nothing. No ping-pong.
   - **I8 A newer build's fields survive** an older build's edit.
   - **I9 References kept**: no device sends a record without a reference iCloud holds unless a person on that
     device made the item or changed that field (section 8).
   - **I10 Accounts apart**: each account's iCloud holds only that account's items.
   As run in round 28 (`SyncCoreSimulationTests`; the commands are at the top of that file): about 3,200 histories
   of 300 to 1,000 steps on three devices, some 310,000 records made and 610,000 saves accepted, 14,000 crashes
   ridden out, 172 conflicts settled. Nineteen kept seeds and a spread of short runs are part of `swift test`.
   As run in round 29, after deletions stopped being read from absence: 5,000 histories of 300 steps on three
   devices (1,000 each of `everyday`, `conflict` and the new `rows`, a store that loses rows; 400 each of `memory`,
   `account`, `zone`, `quota` and `refusal`): 407,000 records made, 783,000 saves accepted, 22,500 crashes ridden
   out, 589 conflicts settled. Compared seed for seed with the engine before: no finding it did not have, and four
   of its failing seeds pass (section 13).
3. The app's parts against an in-memory SwiftData store (every field of every model there and back; an edit made
   while the engine writes is not lost).
4. End to end on CloudKit **Development**: two Debug Mac apps on two side stores, as two devices (run in round
   28: one sent its items, the other, launched empty, showed them all; a task made on the second reached the
   first when it came forward), and the transport's probe (18 steps: every type there and back, a conflict,
   markers, removal for good, a newer build's key, 300 records in two batches, a restart from saved state). Both
   run again in round 30 in the engine's own container, after the review (section 13). The commands:
   `HITLIST_STORE_SUFFIX=<name> …/Debug/HITList.app/Contents/MacOS/HITList -syncTransportProbe YES -disableCloudKit
   YES -ApplePersistenceIgnoreState YES` (and once without `-disableCloudKit YES` for the mirror's step), and
   `open -g -n --env HITLIST_STORE_SUFFIX=<a> --stdout <file> …/Debug/HITList.app --args
   -ApplePersistenceIgnoreState YES -syncEngine own -syncEngineZone <zone> [-seedSampleData]`, twice.
5. The move rehearsed before any real device moves. **Done in round 32** (`dev/briefs/ROUND-32.md` has each run):
   on CloudKit Development with George's iPhone 16 and this Mac as the two devices, Debug builds on side stores,
   driven from a terminal by `SyncEngineRehearsal`'s hooks and judged by Check iCloud… on the engine
   (`SyncEngineAudit`: every record of the zone read afresh and compared field by field) and by the mirror's own
   audit. (a) Both devices on the mirror with the same 30 items, two of them doubled by `id`: moved one after the
   other; each merged the doubled rows, the first sent 31 records, the second found all 30 as it held them and
   sent nothing; ordinary edits on both (completed, renamed, moved, deleted, made) crossed and both compared
   exact. (b) The way back: the Mac first, keeping its file, the mirror sending what changed meanwhile (its audit
   agreed, 19 tasks); the phone with a fresh copy (agreed, 19 tasks, nothing doubled). A second device that came
   back with its own file doubled the items made meanwhile (seen on two Mac stores: 21 tasks where 19 were right),
   which is why the move back asks. (c) George's real tasks, restored on each device from that device's newest
   daily backup (59 tasks and their Groups, labels, filters and Switchboard; the phone's backup a day older than
   the Mac's): sent by the Mac, met by the phone as M3 and M5, identical on both and in iCloud, then edited on
   both through five rounds. Two stores on one Mac cannot stand in for two devices for a fetch: iCloud's change
   feed, like its pushes, does not come back to the device a change was made on.

## 10. Holds and the bolt

The engine is in one state (`SyncStatus`): off, starting, idle, fetching, sending, or **held** for a reason only the
person or the world can lift:

| Hold | When | What the engine does |
|---|---|---|
| `noAccount` | Signed out of iCloud | Nothing is sent or fetched. Parity with the mirror: what was synced leaves the device at sign-out, after a backup is written; it returns at sign-in. A deletion not yet sent is kept and goes at the next sign-in to the same account (round 32) |
| `needsUpdate` | iCloud's format is newer | Nothing is sent or fetched |
| `zonePurged` | The person removed HITList's data in iCloud's settings | Nothing is deleted here by itself. The person is asked: remove here too, or keep and send again |
| `storageFull` | iCloud is full | What is waiting stays waiting; tried again on return to the app |
| `iCloudNotReady` | iCloud refused the send for the build or the account (a schema not yet deployed) | As `storageFull`: what is waiting stays waiting and counted, nothing refused; tried again on return to the app and by Try again, never by a timer |
| `duplicates` | Two rows share an `id` | The app merges them, then the engine starts |
| `failed` | The store or the ledger could not be read or written | Tried again at the next start; the words are one fixed sentence per failure (`SyncFailureWords`) and the error itself is in the sync log only. Also when the ledger's file could not be opened now (no permission, a full disk): no engine runs, the file is left as it is, and deletions made in that launch are not taken down, so those items come back |

A zone lost by reset of encrypted data, or deleted in testing: the ledger is forgotten and everything here is sent
again. **An account switched** from one the device is signed in to, in one order (round 32, brief 160; the mirror's
`AccountSwitch` and the brain used to race): the brain's backup; the previous account's backups set aside by that
backup; every item removed, those iCloud never held too (they would otherwise travel into the next account's
iCloud); the memory forgotten; the new account joined and fetched; `AccountSwitch` does the rest and leaves the
backups alone. A sign-out keeps what iCloud never held, and the ledger keeps the account it was signed out of: a
later sign-in to another account is a switch for the backups, and what the sign-out left stays. The engine's
backup folders are keyed by the engine's container's account ids, so folders set aside under the mirror stay where
they are.

There is no hold for "many items gone": the engine never infers a deletion (section 4), so a store that reads
empty is not a question for the person. It sends nothing and everything comes back.

While held (a full iCloud, or one not ready, excepted) nothing is compared, `recordToSend` answers nil, and fetched records are let go
unread; when the hold lifts the transport is reset, so everything comes again. Deletions the person makes while
held are still taken down and noted. A full iCloud still reads what
arrives and counts what waits, and is tried again on return to the app only (never by itself: no loop).

**The bolt** is filled exactly when: idle, nothing waiting, the first fetch finished, no error. Hollow with the
number when changes are waiting ("3 changes waiting to go to iCloud"). No comparison of every record, no gates, no
guessing; Check iCloud… stays as the person's own audit.

## 11. Moving from the mirror

- **A store syncs on the engine only when it was moved** (from 0.9.14, round 32; George, 2026-11-16: "Please work
  freely and complete the sync engine … I also won't feel comfortable launching until we have at least a few days
  of experience with the new sync system"). Every build may run the engine (`SyncEngineSwitch.isAvailable`); which
  engine a store opens on is the store's own preference (`AppGroup.defaults`, a key per store name), and only the
  move writes it. Every store that was not moved opens on the mirror exactly as before.
- **The switch is hidden.** Settings → iCloud's "Sync engine" group shows after seven taps on the environment row
  ("Production · TestFlight build N"; `SevenTaps`, `SyncEngineSwitch.revealSwitch`), always on a store that is on
  the engine (the way back), and in a Debug build on a side store. Its words speak of "the new sync" and "the
  earlier sync".
- **Moving a device**: a backup; the rows that share an `id` merged; the preference written; the Mac relaunches,
  the iPhone and iPad ask to be reopened (until then the app goes on with the engine it runs, and a move that is
  still waiting can be taken back). The same store file then opens without the mirror
  (`cloudKitDatabase: .none`) and the engine starts with an empty ledger (section 7): the first device sends
  everything, each later one finds its items already there.
- **Move every device, one right after another, changing nothing on a device between the first move and its own.**
  A device on the engine and one on the mirror do not see each other's changes (two containers). What is changed
  on the device still to move, in that window, meets the moved device's copy without a base when it moves: an
  edit made on both keeps the record changed last, whole (M5), and a deletion made on either side comes back (M2,
  M3). The move to the engine warns, and offers "Move anyway", while the mirror's bolt is not filled on that
  device (what it has not yet received would be missing from what it sends).
- **A reinstalled or new device comes up on the mirror**, with the data as it was at the move (the preference lives
  in the App Group's defaults, which go with the app): it is moved like any other device. From the release that
  moves everyone this is no longer so.
- **The way back** (rehearsed, section 9): moving back asks which device this is. **The first device back sends**:
  it keeps its file and the mirror, reopened, sends everything that changed while it was off (SwiftData records
  history on a store open without the mirror). **Every other device downloads**: its store is set aside at the
  next launch (as Reset local cache does, never deleted) and the mirror downloads its zone into a new one. A
  second device that came back with its own file would send the items made on the engine as records of its own,
  and every device would hold them twice. What a device changed on the engine and had not yet synced when it
  downloads is in its backup only. Never install a build from before 0.9.14 on a moved device: it opens the store
  on the mirror as a way back nobody chose.
- **Deletions made during a stint on the mirror come back** when the store returns to the engine: the ledger is
  kept, nobody took those deletions down, and an item iCloud holds that is missing here is brought back (M14). A
  limit, on the safe side.
- **No merge by name on the engine** (round 32): Groups, labels and filters of one name are merged only on the
  mirror, which makes such pairs itself. On the engine a record is named by its `id` and seeds carry stable ids;
  a merge there would delete on every device something a person made on purpose, or strand a task filed into
  the copy that lost. Rows that share an `id`, the profile and the sub-task repair still merge.
- **Check iCloud… on the engine** (`SyncEngineAudit`): a sync, then every record of the zone read afresh by a
  second road (one zone-changes fetch with no token, nothing shared with the engine's bookmark) and compared with
  the device field by field. It repairs nothing; the sync log names each record that differs, by key and field.
- The engine's container's Production schema is deployed before the release that lets a store move (section 3).
  The tasks' container needs nothing for the engine, ever.

## 12. Decisions that are George's

0. **A container of its own for the engine: decided and done, 2026-11-16** (`iCloud.com.trammells.hitlist.sync`;
   section 3). He reset the tasks' container's Development side that evening; nothing of the engine's is there.
1. **Plain fields: decided, 2026-11-16** ("we don't need encryption right now; this is not something I plan to put
   on the App Store, only to share with friends"). Fields are stored as the mirror stores them (protected by the
   account, readable in the CloudKit Console for support). Encrypting titles, notes and names later is one format
   version and a re-send.
2. **Sign-out removes what was synced from the device** (as the mirror does), after a backup; it returns at
   sign-in. Built that way. **Open, for the release that moves everyone**: iCloud switched off for HITList alone
   may be announced as a sign-out, and the supervisor's recommendation is to keep the tasks on the device at a
   sign-out and remove them only when a different account signs in.
3. **A purge in iCloud's settings asks** instead of deleting the device's copy (Apple's guidance is to delete).
4. **When devices move**: his first (0.9.14, the hidden switch), then friends, in a release that moves each device
   at its first launch. **He is told ahead of anything that could wipe, hide or fail to carry over a friend's
   data, so they can export first** (his word, 2026-11-16).

## 13. Open, as round 32 left it

**Closed in round 32** (each with its test or its run; `dev/briefs/ROUND-32.md`): a fetched record that cannot be
read (16c), an expired change token (16e), the ledger moved aside for any error (brief 149); the simulation's
standing failures, fixed or pinned as limits (brief 150); a fetch after a relaunch that asked iCloud nothing, and
the push subscription (section 6a); a reset that let the old engine write its bookmark back (review 148); the
release guard blind to a field missing from both environments (the schema file, section 3); the merge by name on
the engine and Group pairs of one name (finding 14; section 11); the move stopping the engine on a phone; a
deletion through the app on the real service (dozens, in the rehearsal); the move from the mirror and the way back
(section 9, item 5); and by brief 160: a Production schema not yet deployed refusing every record for good (now
the `iCloudNotReady` hold), a deletion's note forgotten while its save was still committing (notes for rows still
here are kept until the launch's whole compare), a hold's words (never a Swift error), the account switch's two
owners, and items iCloud never held travelling into another account.

**Open:**

- **A push from the phone to this Mac was not seen** on the night of round 32 (no push reached the Mac's push daemon
  at all), after the engine's Development side had been reset; the Mac to the phone was, within seconds, and in
  round 31 both were. On a Mac with a TestFlight build and a Debug build of one bundle the two register different
  push tokens, which may be the whole of it. George's first week on real builds says: the sync log's "Sync for a
  push" lines. **A push that has to launch the app** is still unproven (the phone locked before the test).
- **The engine in Production**: nothing has run there. Stage 5 is that proof.
- **One contract suite run against both the pretend iCloud and CloudKit** (stage 2, item 6): not built. The probe
  proves the transport's rules on the service in the mode the app now runs; the pump is proven on the pretend
  iCloud and on two devices. A shared suite remains worth having before the mirror retires.
- **The two simplifications** the second review named (one recovery path for the brain's half-failed steps; a
  sub-task under a deleted task left to its own marker): not before the first live week, for the reasons brief 150
  gave (`switchTo` guards an account switch whose backup failed and cannot become "merge afresh"; the sub-task
  rewrite would show sub-tasks loose for a moment, and for good when a child's marker never comes).
- **A zone deleted while a device is offline, then that device's sign-out**, removes an item its ledger calls
  synced that iCloud no longer holds, with an edit not yet sent: only the backup has it (the simulation's `all`
  set, seed 6; the engine before round 32 fails the same way; `all` mixes every fault and is not one of the eight
  sets the exit line names). The smallest fix: at a sign-out keep the items whose last save was never followed by
  a fetch. It goes with the sign-out decision below.
- **Records owed** (brief 149's "brain gap"): a fetch that left records owed is still not counted as whole from
  its first telling, and the owed words show from the second fetch.
- **The status line shows iCloud's own words** for passing trouble that has lasted a while
  (`SyncStatus.lastError`), raw. Holds have plain words; this does not yet.
- **A sign-out** (section 12, decision 2): whether iCloud switched off for HITList alone is announced as a
  sign-out is not known (no session may sign a device out), and if it is, the tasks leave the device until
  sign-in. To decide before everyone moves.
- **A device reinstalled or new comes up on the mirror** with stale data until it is moved (section 11): fine while
  only George's devices move; before everyone moves, either the release moves every device at launch (stage 6) or a
  mirror launch looks once for the engine's zone and says so.
- **"Delete all data from iCloud"** (`AccountCopy.deleteAll`) speaks of one entry in iCloud's storage settings;
  with two containers there may be two. To be read off a device once the engine's container holds data.
- **Deletions made while the engine cannot run** (the ledger's file could not be opened; a stint on the mirror)
  are not taken down: those items come back. The safe direction; SwiftData's own history as the record of a
  deletion (a model change, stage 7) closes it.
- **A launch before the phone's first unlock** opens the empty in-memory fallback, and that process lives on after
  the unlock (brief 149's A1, to check; it is so on the mirror too). The engine never runs on the fallback.
- **A store file put back from an older copy beside a newer ledger** (the first review's finding 19): nothing is
  deleted and items made since come back, but the older values of items changed since go to iCloud over the newer.
- From the second review, unchanged: the ledger keeps a copy of every record as its base; `CloudSyncMonitor`
  carries a branch for the engine that goes when the mirror retires.
- The limits of section 5 are limits, not open work.

## 14. The road to switching it on

George, 2026-11-16: "Please do plan the engine's next steps." Seven stages. A stage is done when its exit line is
true and its evidence is written here; nothing in a later stage touches real data before the stage before it is
done.

**Stage 1. On real devices. Done, round 31.**

**Stage 2. Close what can lose or hide a change. Done in round 32**, items 1 to 5 (briefs 149, 150, 160 and the
supervisor; section 13 lists what closed), and one item nobody had listed: the engine did not catch up after a
relaunch (section 6a). Item 6 (one contract suite on both clouds) and item 7 (the two simplifications) are open
and deliberately after the first live week (section 13). Exit met: 1,000 histories of every fault set with no
failure that is not a written, tested limit; no open finding that can lose a person's change.

**Stage 3. George's decisions. Done**: plain fields (section 12). The sign-out's behaviour stays as built for his
own week and is to be decided before everyone moves.

**Stage 4. The move, rehearsed. Done in round 32** (section 9, item 5): two real devices, the mirror to the engine
and back, a copy of his own tasks from each device's backup, every comparison by the audit and not by eye.

**Stage 5. Live for George only: ready.** 0.9.14 lets a store be moved. In order:

1. The engine's container's Production schema: its Development side holds exactly `dev/cloudkit/sync-engine.ckdb`
   since 2026-11-16; George deploys it (CloudKit Console → `iCloud.com.trammells.hitlist.sync` → Development →
   Deploy Schema Changes…). `scripts/release.sh` refuses to upload until Production holds it.
2. He releases 0.9.14 and installs it on the Mac and the iPhone.
3. With the bolt filled on both: Settings → iCloud (iPhone: iCloud & data), seven taps on the row that reads
   "Production · TestFlight build …", then the "Sync engine" group at the foot of the page → Move to the new sync.
   The Mac first (it relaunches), then the iPhone at once (it asks to be reopened), changing nothing in between.
4. A week of use. Each day or so: Check iCloud… on both. The sync log holds every fetch, send and push.

Exit: a week with no hold he did not cause, no change stranded, the bolt true, and Check iCloud… finding iCloud
and the device the same on both. The way back, if it is ever wanted: Move back on the Mac ("First device"), then
on the iPhone ("Another device already moved back").

**Stage 6. Everyone.** A release that moves each device at its first launch after updating, after a backup, with
one screen that says so. **Before it, George is told what a friend should do first** (export: Settings → iCloud &
data → Export JSON…) **and what could go wrong for them**: a friend whose two devices update days apart has, in
between, one device on each sync; what they change on the device still to move meets the other's copy without a
base (section 11). Nothing is deleted by the move itself. The way back is kept for the releases that follow.
Exit: every friend's devices moved; two weeks without a sync report.

**Stage 7. The mirror retires.** Removed: the mirror's configuration, the instruments built to guess what it knows
(`CloudSyncMonitor`'s reading of its events, the gates, the comparison of every record, the watchdog), Check
iCloud…'s repairs; SwiftData's own history takes over as the record of a deletion (a model change, so it rides
this release). The app is then smaller than it was before the engine.

**Not on the road, on purpose**: no server of our own, no per-field clocks or CRDTs (a record settled three ways
with the later record winning a true conflict is enough for one person's tasks), no second transport, no remote
switches. Each would be more machinery than this app's sync needs.
