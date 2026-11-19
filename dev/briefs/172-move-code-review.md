# 172: the move's code as it is now, read line by line for bugs (a review; no code)

Round 34's supervisor rewrote the move made by the app itself after brief 171's review of its design, and nobody
has read the result. The next build runs this code once on every tester's device, with their tasks. **Read it as
the person who will be blamed**: every line of what changed, for bugs, not for design (the design's decisions are
in `dev/SYNC-ENGINE.md` section 14, stage 6, and sections 10 and 11; 171's findings and what was done about each
are in `dev/briefs/ROUND-33.md` and the stage's own text. A decision you think is wrong goes in one line under
"Design", after the bugs).

**What to read** (`git diff 4f905c03..HEAD -- HITList HITListTests HITListCore` shows all of it; read each file
whole, not only the hunks): `HITList/Services/SyncEngine/SyncEngineAutoMove.swift`, `SyncEngineMoveFinish.swift`,
`SyncEngineMoveCheck.swift`, `SyncEngineRollout.swift`, `SyncEngine+Move.swift`, `SyncEngineSwitch.swift`,
`SyncEngineRehearsal.swift` (Debug only: lower priority); `HITList/Services/Deduplicator.swift` (the untouched
seed, the merge on a store that came back); `HITList/Services/LocalBackup.swift` (the kept copy, the set-aside);
`HITList/Services/Sync/AccountSwitch.swift`; `HITList/Views/Popouts/PopoutController.swift` (`isAnyCardOpen`);
`HITList/Views/Settings/SyncEngineSettings.swift` (the hidden group's new rows); `HITList/HITListApp.swift` (the
three launch hooks and the scene hook); and their tests under `HITListTests/SyncEngine/` and
`HITListCore/Tests/…/SyncCoreMoveFromTheMirrorTests.swift`.

**What to look for, concretely**:
1. **The runner's states** (`SyncEngineAutoMove.Runner`): can `move()` run twice in one launch or across the look,
   the question and the mirror's changes arriving in any order; can it move with a stale `facts()` (the mirror
   fell behind between the decision and the move); can `evaluate()` re-enter itself through `zoneLooked` or
   `wordAnswered` in a way that skips a guard; does every path clear `isLooking` / `isAsking`; what happens when
   the look or the question never returns; what `withObservationTracking` misses (a change between the read and
   the re-arm); what a second window or a widget's launch of the app does to `Runner.shared`.
2. **The finish** (`SyncEngineMoveFinish`): every way the iPhone could end its process at a wrong moment (a card
   open that `isAnyCardOpen` does not see: an editor in a sheet, Settings' text fields, Review Inbox, a share
   sheet, Siri or a widget intent running the app in the background, a background refresh, the engine or the
   mirror half way through a send, a backup being written, a notification being scheduled); whether `exit(0)`
   after `stop()` can cut a write; whether the Mac can relaunch under a typed quick-add row, a sheet, a second
   window, a menu held open; whether the loop guard (`givesUp`) holds in every order of keys; what the hand move's
   own flows now do differently (the way back included) and whether its words are still true.
3. **The check** (`SyncEngineMoveCheck`): can it run while something is waiting or mid-send; can its observer leak
   or fire twice; does a failure burn a try.
4. **The word** (`SyncEngineRollout`): every CloudKit error mapped on the safe side; the query path (any record
   of the type, newest wins) with zero, one, several records, a deleted one, a paused newest and a go older; a
   field of the wrong kind; what `minBuild` does with this build's number under TestFlight and under Debug.
5. **The merges** (`Deduplicator`): can the untouched-seed rule ever make the wrong row win or delete a row a
   person changed (two devices that both seeded, an engine seed stamped 2001, a seed edited within a second of
   being made, a Group or label with a name-based id); can `mergeSharedIDs` on a came-back store delete something
   the mirror then deletes on every device that should have stayed.
6. **The backup** (`LocalBackup`): the kept copy's name against the rotation, the import, the set-aside in both
   directions, a second move on the same day, a folder that cannot be written.
7. **What the tests do not hold**: for each rule in stage 6, is there a test that fails if the rule is broken? Name
   the rules that could be broken with every test still green.

**Read-only**: change no tracked file, commit nothing; a test you write to prove a bug stays uncommitted and goes
into your report as text. Nothing of yours talks to iCloud or uses a device. Run what you like in your own
worktree (`swift test` in `HITListCore`; `xcodebuild test … -only-testing:HITListTests/<class>` on the Mac with a
derived-data folder of your own).

**A finding**: numbered; **A** (a tester's data lost, hidden, doubled or overwritten; a device that stops syncing;
the app ending itself wrongly or in a loop), **B** (wrong words, a wrong state shown, a rule that can silently
not hold), **C**; the sequence that triggers it; `path:line`; how sure (**certain** only if you traced or ran it);
the smallest fix as a diff or a few lines. No praise, no restating what is right.
