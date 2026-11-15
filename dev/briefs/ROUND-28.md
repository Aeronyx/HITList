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

## Wave 1 as it went (03:30 to 05:00)
All five reported early and all are on master (core 737 → 1,013 tests). What they found mattered more than what
they built: the merge rules had six holes (138, with 95 tests and 21,700 generated cases); SwiftData's main context
does not take in another context's save, so the engine writes through the main context (141); the mirror imports
every zone of its container and mangled the engine's records, so record types are `HL` + the type and the engine is
meant for a container of its own (142's probe on Development); nothing guarded iCloud against a store that reads
empty, so there is a mass-deletion hold (139); the design's rule for a reference whose target had not arrived lost
labels, Groups and parents, and is rewritten (140's rig, seed 58); a transport that lost its state must take the
ledger with it (140's rig, seed 4). The design was corrected nine times in ninety minutes, each time on evidence.

## Wave 2 (05:15, four sessions, all Opus 5.5 at xhigh)
| Brief | Session | What |
|---|---|---|
| 143 | `sync-wire` | The engine in the app behind the switch: life cycle, the mirror's events fed on the engine, the move, Reset local cache, two whole devices in hosted tests |
| 144 | `sync-status` | The bolt and Settings → iCloud on the engine's own status: exact counts, the holds and their buttons |
| 145 | `sync-sim` | The brain on the rig: thousands of random histories, every fault, I1 to I9, fixes |
| 146 | `sync-review` | An independent review of the whole, findings proven by tests |

The supervisor's own: the seam between 143 and 144 (`SyncEngineBoard`), `release.sh`'s schema check, the run of two
devices on CloudKit Development, the record, the hand-over.

## The supervisor's own
- The Theme menu (done), its pictures.
- The design, the contract, `RecordMerge`.
- Merging the waves, the suites, the end-to-end run on Development, `## 0.9.12`, the record, the hand-over with
  the decisions that are George's (`dev/SYNC-ENGINE.md` section 12).
