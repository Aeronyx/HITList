# Brief 146: an independent review of the sync engine (session `sync-review`, effort xhigh)

HITList's own sync engine was designed and built in one night by one supervisor and five sessions. Every tester's
tasks will pass through it. You did not write any of it, and that is the point: read it as someone who expects to
find the bug that loses a person's data, and prove each one you find.

**Clock** (Eastern, `TZ=America/New_York date`): findings to the supervisor **as you find them** (each one alone is
worth more now than a list later); a written review by 06:50.

## Read first
`dev/briefs/COMMON.md` (the Round 28 block and its wave-2 addendum), `dev/briefs/ROUND-28.md`,
**`dev/SYNC-ENGINE.md`** (the design: read it first as a design, before any code, and note where it would fail),
then the code on master: `HITListCore/Sources/HITListCore/Sync/` (contract, merge, brain, pretend iCloud) and
`HITList/Services/SyncEngine/` (the SwiftData store, the ledger, the CloudKit transport, the probe), their tests,
and in the notes folder `round-28/SDK-CKSyncEngine.md` (what Apple's engine is documented to do and not to do),
`round-28/DATA-LAYER.md` section 0, and the four reports (`138-…/REPORT.md` … `142-…/REPORT.md`) **last**, so that
you form your own view before you read what the authors think they proved.

## Yours
Nothing in Sources. New test files only, for findings you can reproduce:
`HITListCore/Tests/HITListCoreTests/Sync/SyncReviewFindingsTests.swift` (on `MemoryLocalStore`, `MemoryLedger`,
`FakeCloud`) and `HITListTests/SyncEngine/SyncReviewFindingsTests.swift` (on an in-memory SwiftData container). A
test that shows a bug fails; so that the suites stay green, wrap its failing assertion in `XCTExpectFailure` with
the finding's number and one line, **strict**, so it turns red the day the bug is fixed and somebody takes the
wrapper off. Your notes and the review itself go in `146-sync-review/` in the notes folder.

Not yours: every source file (sessions 143, 144 and 145 are working in the app and the core right now; a fix is
theirs or the supervisor's), `dev/`, `scripts/`. You never talk to iCloud.

## What to look for (a floor, not a list to tick)
- **A person's data lost or wrong**: an edit overwritten by an older value; an item deleted that nobody deleted; an
  item back that was deleted; a label, a Group or a parent dropped; two items where there was one; anything of one
  iCloud account reaching another. For each, the smallest sequence of events that does it.
- **A crash at the worst moment**: between any two writes (the device, the ledger, the transport's state, iCloud).
  The design claims every such state is read correctly afterwards (section 4): find the pair of writes for which it
  is not. Power loss rather than a clean kill. A ledger file that is half there. A store reopened after a reset.
- **Concurrency**: the brain's one queue (can two things interleave after all? can it deadlock with the transport,
  the store's hop to the main actor, or the host?); `CloudKitTransport` as an actor that is also its engine's
  delegate (events arriving while it awaits the brain; `stop()` and `reset()` in the middle of anything); the
  SwiftData store's main-context writes against a person typing; `Sendable` claims that are not true
  (`@unchecked`, `nonisolated(unsafe)`).
- **CloudKit as it really is**: what the transport assumes that `SDK-CKSyncEngine.md` does not say; record and
  request size limits (a long note, 5,000 pending records, a 200 KB picture); an asset left on disk; the zone's own
  save refused; a token from another zone; what an older build of the app does when a newer one has written a
  field or a type it does not know (the design's promise: it leaves them alone).
- **The merge's rules against real use of this app**: a repeating task completed on two devices; a switch flipped
  on two; a sub-task moved while its parent is deleted elsewhere; the day anchoring's rewrite on two devices in
  two time zones; the name merge deleting a duplicate Group on two devices at once; the profile; an import of 800
  tasks from Todoist and its undo.
- **The holds**: can the engine get stuck with no way out, or leave a hold it should not? Can the mass-deletion
  guard be walked round, or fire on something ordinary?
- **What the tests do not test**: claims in the reports with no test behind them; tests that would pass if the
  code under them were deleted.
- **The design itself**: anything in `dev/SYNC-ENGINE.md` that is wrong, missing, or promised and not built.

## How to report a finding
To the supervisor at once (`mcp__ccd_session_mgmt__send_message`, `session_id: "parent"`): a number, one sentence
of what goes wrong for a person, the sequence that does it, where in the code, how sure you are (reproduced by a
test / read from the code / suspected), and what you would do about it. Then the test, if there can be one.
Severity in plain words: loses or corrupts data; wrong until the next sync; stuck; cosmetic.

## Done when
`146-sync-review/REVIEW.md` holds every finding in that form, ordered by severity, with the tests' names; a short
list of what you examined and found sound (so the supervisor knows what was looked at); and the three things you
would not ship without. Core tests and the Mac suite pass with your wrapped tests in them (counts).
