# Round 28: 0.9.12, the Theme menu put right, and HITList's own sync engine begun (2026-11-15, from 02:56 Eastern)

0.9.11 was released (George accepted Apple's agreement and ran the release himself). His message at 02:56 Eastern,
verbatim:

> Forms signed on your suggested links. Release 0.9.11 successful.
>
> Why did all the creatures in the Theme menu get so small? And why does Quill look like he's melting in the Theme
> menu now? I simply wanted you to position Quill properly, not change his Theme menu sprite. Please reassess.
>
> If we need to make our own engine for proper cloud sync, let's get started. I want it to be professionally built.

## How it is read
- **The Theme menu** (the supervisor's own, done before the sessions started, commit `f8d9d7a`). Nothing changed
  the creatures' size between 0.9.9 and 0.9.11: the Mac's page has always drawn them at the iPhone's point a pixel
  on boxes half as big again, and the hand-over picture of round 27 was that page. The Mac's swatch is now the
  iPhone's one and a half times the size, creature and all. Quill's frame drawn for the swatch in round 27 (bent
  round the corner: "melting") is gone; he sleeps in `drape`, his own pose, every pixel, moved 6 pt left of
  0.9.9's place so that he rests on the box instead of hanging beside it. Lesson: "position him properly" was a
  request to move a sprite, and a session answered it by drawing a new one.
- **The engine.** George said go, and "professionally built". So: a design written down before any code
  (`dev/SYNC-ENGINE.md`), a contract in code the parts are built against (`HITListCore/Sources/HITListCore/Sync/`),
  the brain pure and tested without CloudKit, a pretend iCloud that keeps the same rules as the real one so that
  several devices, thousands of edits and every failure can be simulated, and nothing a tester has moved until the
  move has been rehearsed. Released builds keep the mirror until George says otherwise; the engine ships dark.
  Round 27's instruments round the mirror (the record check, the gates) stay as they are for as long as the mirror
  is what released builds run.

## Wave 1 (all Opus 5.5, five at once; the supervisor wrote the contract and the merge rules first)
| Brief | Session | Effort | What |
|---|---|---|---|
| 138 | `sync-proof` | xhigh | The merge rules and the contract proven: every rule, properties, a second pair of eyes on the supervisor's own code |
| 139 | `sync-core` | xhigh | The brain: `SyncCore` on the contract's protocols, every transport rule and every hold |
| 140 | `sync-fake-cloud` | xhigh | A pretend iCloud that keeps the transport's rules, with every failure on a switch, and the simulation's rig and invariants |
| 141 | `sync-swiftdata` | xhigh | The six models as records and back (`SyncLocalStore`), and the ledger on disk (`SyncLedger`) |
| 142 | `sync-cloudkit` | xhigh | `SyncTransport` on `CKSyncEngine`, `CKRecord` both ways, a probe that proves it on CloudKit Development |

All xhigh: this is the layer every tester's data will pass through, and a mistake in it is not seen until it has
cost someone a task.

## Wave 2 (briefed when wave 1 is on master)
The engine wired into the app behind the switch (life cycle, the mirror's events re-pointed, the move from the
mirror, Reset local cache), the bolt and Settings → iCloud on the engine's own status, the simulation at scale
with every invariant, an independent review of the whole, end to end on CloudKit Development with two side stores,
the schema's guard in `release.sh` for the new record types.

## The supervisor's own
- The Theme menu (done), its pictures.
- The design, the contract, `RecordMerge`.
- Merging the waves, the suites, the end-to-end run on Development, `## 0.9.12`, the record, the hand-over with
  the decisions that are George's (`dev/SYNC-ENGINE.md` section 12).
