# 167: the move to the new sync, made by the app itself: designed, built, and switched off (code)

George, 2026-11-18: "I'd even rather the update just automatically move their tasks after we've confirmed the new
engine is working. The less technical stuff my friends have to deal with, the better." This is stage 6 of
`dev/SYNC-ENGINE.md` section 14 (read sections 7, 10, 11, 13 and 14 whole, then `SyncEngineSwitch.swift`,
`SyncEngine+Move.swift`, `SyncEngineSettings.swift`'s switch group and how `HITListApp` and `ModelContainerFactory`
choose the engine at launch). 0.9.15 ships it **switched off**: one constant, `SyncEngineSwitch.movesByItself`,
false, pinned by a test that says in its name that George's week comes first. Nothing a released 0.9.15 does may
differ from today while it is false; prove that with a test of the launch's decision.

**The design is the work; write it before the code** (in your report, as the text for section 14's stage 6; the
supervisor edits the document). It must answer each of these with a rule, and each rule gets a test named after it:

1. **When a device moves.** Not "at first launch after updating" blindly: the hand move warns while the mirror's
   bolt is not filled, because what the device has not yet received would be missing from what it sends. So: on a
   launch on the mirror, once the mirror has caught up (the bolt's own condition, the one the hand move's warning
   reads), after a backup that succeeded, the preference is written and takes effect at the next launch (the
   iPhone cannot relaunch itself; a waiting move already exists: `SyncEngineSwitch.pendingMove`). Decide whether
   the Mac relaunches by itself or waits too (a relaunch nobody asked for, mid-typing, is a fault). Never while
   signed out, while a hold stands, while duplicates are unmerged, or on the in-memory fallback; never twice; a
   move that failed says so in the sync log and is tried at a later launch, not in a loop.
2. **A person with two devices that update days apart.** Section 11: a device on each sync do not see each other;
   what changes on the one still to move meets the other's copy without a base (the later record wins whole;
   a deletion made on either side comes back). Nothing is lost, but it must not last silently. Rules to decide:
   a mirror launch looks once per launch for the engine's zone in the engine's container (one CloudKit call, no
   record read; section 13 proposed it); finding it means another device of this account has moved, so this one
   moves as soon as rule 1 allows and, until it has, the bolt's words say that this device is waiting to join the
   new sync; a device on a build older than 0.9.15 cannot know, so the moved device's What's New line and the
   status page say once that the other devices need the update.
3. **A device installed fresh after the account moved** (a new phone, a reinstall). Today it comes up on the
   mirror and downloads the tasks' container's zone **as it was at the move**: stale items, and everything deleted
   since. Moved with the ordinary merge, those deleted items would come back on every device. So a store that has
   never held anything of its own and finds the engine's zone must take the engine's copy and not merge the
   mirror's stale one in: the existing "another device already moved" road in reverse (`freshCopy`: the store set
   aside at the next launch, never deleted, and the engine downloads into a new one). Say exactly how "never held
   anything of its own" is known (nothing made or changed on this device since install; the mirror's download
   alone does not count) and what happens when it cannot be known (the safe side: merge, items come back, nothing
   is lost). Say what the person sees between the first launch and the reopen, and make it one calm line, not an
   empty app with no explanation.
4. **What the person is told**: one line in What's New (the supervisor writes it; give the words) and nothing to
   tap. The hidden group stays as the way back.
5. **What could hide or fail to carry a friend's data**, in order of likelihood, each as a sequence of steps, and
   for each whether an export first would protect them (George tells his friends before the release that moves
   them; this list is what he tells them from).

**Then build it**, behind the constant: a pure decision (`SyncEngineAutoMove`, a new file: what this launch should
do, from the store's state, the mirror's state, the zone's presence, the account, the constant) with a test per
rule; the look for the zone (the engine's container only; never a record; never when the constant is false);
the wiring at launch and where the mirror's bolt fills. **Yours**: `SyncEngineSwitch.swift`, `SyncEngine+Move.swift`,
the new file, `SyncEngineSettings.swift`'s switch group (agent 165 edits the hold's words in the same file: keep
your hunks apart), the smallest hook in `HITListApp` or `SyncEngineHost`, tests. **Not yours**: `SyncEngine.swift`,
core's `Sync/` (165), `CloudKitTransport.swift`, the mirror's side beyond reading its state, `ICloudSettingsGroups.swift`
(163), the models, `dev/`.

Nobody talks to iCloud in this round: the look is proven against a stand-in (a protocol with a test double), not
the service; no probe, no rehearsal, no device. Proof: the tests; `HITListTests` whole on the Mac at the end. Your
report: the design text; each rule and its test; what the constant's flip would still need before it is safe
(a rehearsal on two devices of each rule: write its steps as commands the supervisor can run, in the style of
section 9's item 5); and anything in the existing move you found wrong while reading it, as findings.
