# Brief 145: the brain on the rig: many devices, every fault, every invariant (session `sync-sim`, effort xhigh)

HITList's own sync engine has a brain (`SyncCore`, session 139) and a pretend iCloud with a simulation rig and nine
invariants (session 140). They were built side by side and have never met. You plug the brain into the rig, run it
hard, and fix what it finds. This is the proof George's "professionally built" rests on: when you are done, a
claim like "nothing a person changed is ever lost" is a test that runs thousands of random histories.

**Clock** (Eastern, `TZ=America/New_York date`): first results to the supervisor by 05:50 (the kept seeds and 100
random ones: clean or what they found); report by 06:50.

## Read first
`dev/briefs/COMMON.md` (the Round 28 block and its wave-2 addendum), `dev/briefs/ROUND-28.md`,
**`dev/SYNC-ENGINE.md`** (all of it: it is the specification you test against; sections 5 to 9 closely), in the notes
folder **`140-sync-fake-cloud/REPORT.md`** (the rig's calls, the kept seeds, the two open seeds, how to replay) and
its `NOTES.md`, **`139-sync-core/REPORT.md`** (the brain's calls, its choices, its "not built" list),
`138-sync-proof/REPORT.md` and `ITEM5-design-vs-code.md` (the merge's limits), then all of
`HITListCore/Sources/HITListCore/Sync/` and its tests.

## Yours
Everything in `HITListCore/Sources/HITListCore/Sync/` **except the contract files** (`SyncRecord`, `SyncSchema`,
`SyncTransport`, `SyncStorage`, `SyncMemory`: a flaw in one is a diff in your notes folder and a message to the
supervisor at once): the brain (`SyncCore*.swift`, `SyncStatus`, `SyncHost`), `RecordMerge.swift`, the rig
(`Testing/*`), and all the sync tests. New: `HITListCore/Tests/HITListCoreTests/Sync/SyncCoreSimulationTests.swift`
and what you need beside it.

Not yours: anything in the app (sessions 143 and 144 are wiring the engine in and drawing its status now, against
the brain's public surface as `139-sync-core/REPORT.md` gives it: **do not change a public name or signature of
`SyncCore`, `SyncStatus`, `SyncHold` or `SyncHost`**; if a fix needs one, ask the supervisor first), `dev/`,
`scripts/`.

## Items, in this order
1. **Plug it in**: `SyncCore` as a `SimBrain` (a small adapter in the tests). `testKeptSeeds` with it, then the two
   open seeds (39: I9 with the test brain; 34: I2 under lost memories). For each finding decide which is wrong: the
   brain, the merge, the rig's model, or the design. Fix the first three with a test that failed first; the fourth
   goes to the supervisor at once with the trace, and you carry on.
2. **Many seeds, release builds** (the commands are in 140's report): everyday faults, 1,000 seeds × 300 steps and
   200 × 1,000; `memory` (lost ledgers and zones), `zone`, 300 seeds each; then the faults 140 left unasserted
   because its test brain could not do them: **sign-out, sign-in and an account switch** (section 10: what was
   synced leaves the device after the backup, items iCloud never held stay; nothing of one account reaches
   another), **a full iCloud**, **a refusal for good**, **a purge and both answers**. Extend the rig's model where
   it cannot yet judge these (the model must say what should be true after a sign-out; write it down in the
   test's comment in the design's words).
3. **The invariants I1 to I9 hold on every run**, or the finding is explained and either fixed or written into the
   design's limits by the supervisor. Keep every seed that ever failed in `keptSeeds` with one line on what it
   found. Print, for the report: seeds run, steps, records made, saves accepted, conflicts settled, crashes ridden
   out, findings.
4. **What stays in `swift test`** (the whole package must stay under a minute on the CI runner, which is slower than
   this Mac): the kept seeds and a fixed spread of a few dozen short runs across the fault sets. The long runs are
   a command, documented at the top of your test file and in your report.
5. **The open edges** from the wave-1 reports, each decided with the supervisor if it changes a rule, tested
   either way: a sub-task changed here and not sent when its parent's deletion arrives (139); an unsent edit that
   did not move `updatedAt` after a lost transport state (139); a save whose answer was lost leaving no base (140's
   reviewer); the guard's numbers on small accounts (139).
6. **Determinism**: a seed replays exactly, here and under `SWIFT_DETERMINISTIC_HASHING` unset; if the brain lets
   hashing order decide anything, fix the brain.

## Rules
- A red invariant is never made green by weakening the invariant. If the invariant is wrong, say why, and the
  supervisor changes the design's words first.
- Every fix in the brain or the merge has a small test of its own (not only a seed), named for what was wrong.
- No sleeping, no real time, no network.

## Done when
`cd HITListCore && swift test` passes in under a minute (counts before and after); the long runs' numbers are in
the report with their commands; every finding is listed with its seed, what was wrong and where it was fixed; and
the report says plainly what is still not proven.
