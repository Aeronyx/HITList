# 150: the simulation's standing failures, each fixed or pinned as a written limit (code, core only)

`dev/SYNC-ENGINE.md` section 14, stage 2, item 5. A worktree of your own; `swift test` in `HITListCore` is your
build and your proof (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; the long runs add
`-Xswiftc -DDEBUG`; the commands are at the top of `SyncCoreSimulationTests.swift`). No Xcode build is needed.

**Yours**: everything under `HITListCore/Sources/HITListCore/Sync/` and `HITListCore/Tests/HITListCoreTests/Sync/`.
**Not yours**: anything in `HITList/` (agent 149 is changing the transport and the ledger's store; if a fix of yours
needs the app side to change, say exactly what in your report); `dev/SYNC-ENGINE.md` (give the words for section
5's "Known limits" and section 13 in your report; the supervisor writes them in).

Read first: `dev/SYNC-ENGINE.md` whole, sections 4, 5, 7, 8, 9 and 13 closely; in the notes folder (one level above
`round-32/`) `145-sync-sim/` and `146-sync-review/FINDINGS.md`; `dev/briefs/ROUND-29.md` (how deletions stopped being
read from absence, and what the review removed).

## What to do

Section 13 lists the seeds that fail (`SyncCoreSimulationTests.testTrace`, 300 steps, three devices):

- **A Group deleted and put back around an unsent change**: everyday 210, 261, 559.
- **Copies that meet by M5, where one device's record wins whole and the other's label or parent is lost**: zone 270
  (after a lost zone every device sends everything again), refusal 314, rows 174 and 805 (a deletion racing two
  devices that each bring the item back).
- **A person's change to a reference whose row the store had lost**: rows 5, 196, 967.
- **Singles**: memory 36, account 362 (a Group's deletion against a sign-out), quota 59, refusal 148.

For each kind, in this order: replay it and confirm it still fails on this tree; trace it to the one rule or step
that produces the wrong end; then decide.

- **Fix it** when the fix is a rule that is simple to say, can be said in section 5's table, and cannot delete in
  iCloud what no person deleted. The engine going live for one person with two or three devices is what this must be
  right for: a person's edit silently lost on an ordinary day (a Group deleted and put back, an undo) deserves a fix;
  a contest that needs three devices and a lost zone in the same minute may be a limit.
- **Or write it down as a limit**: a test named for what it pins (`testLimit…`) that fails if the behaviour changes
  either way, a sentence for "Known limits" in a person's words (what they would see), and the invariant taught to
  tell that one signature from a real failure **as narrowly as possible** (never a blanket tolerance: a limit that
  makes the rig blind to a neighbouring bug is worse than a red seed).

Hard rules: never read absence as a deletion; never add a flag, a mode or a recovery path where an existing rule can
be made right (the second review counted the flags; do not add to them); a failing seed that looks new is compared
with the commit before (a detached worktree, the same command) before it is called new; `RecordMerge` stays pure and
its property tests (order independence, idempotence) stay green and are extended for every rule you change.

Not this brief: the two simplifications the second review named (one recovery path in place of the flags
`heldUnder`, `joinTo`, `switchTo`, `holdNote`; a sub-task under a deleted task written out and left to its own
marker). Do not do them. At the end, knowing the code, say in a paragraph each whether you would do them before the
engine goes live, and why.

## Exit

`swift test` green. 1,000 histories of 300 steps of every fault set (`everyday`, `conflict`, `rows`, `memory`,
`account`, `zone`, `quota`, `refusal`) with no failure that is not one of your written, tested limits: give the
counts per set, the seeds that fail and which limit each is. Every seed named above is in the kept seeds with its
verdict. Test counts before and after.
