# 165: on the engine, signing out of iCloud keeps the tasks on the device (code)

George, 2026-11-18: "definitely keep tasks on the device after sign-out if possible". Until now
(`dev/SYNC-ENGINE.md` section 10, `noAccount`; section 12, decision 2; section 13's two sign-out items) the engine
did as the mirror does: at a sign-out, after a backup, what was synced leaves the device and returns at sign-in.
iCloud switched off for HITList alone may be announced as a sign-out, so a friend who flips that switch would see
an empty app. **The new rule, for the engine only** (the mirror is Apple's and removes its copy itself; nothing of
the mirror's side changes):

- **A sign-out removes nothing.** Every item stays on the device and can be read and changed. Nothing is sent or
  fetched; the hold's words say that the tasks are on this device only until the person signs in. What is changed
  while signed out waits and is counted, as changes made offline are.
- **A sign-in to the same account** carries on: the ledger and its bases are as they were, so what changed here
  and what changed in iCloud meanwhile settle three ways as after any time offline. Deletions made while signed
  out go up (they are taken down and noted while held: section 10 says so already; prove it for this hold).
- **A sign-in to a different account** is the switch, in the order round 32 fixed (the brain's backup first; the
  previous account's backups set aside; every item removed, those iCloud never held too; the memory forgotten; the
  new account joined and fetched). Unchanged, except that what was changed while signed out is now part of what
  that backup holds: prove the backup is written before anything is removed and that it holds those changes.
- **A zone deleted while this device was away, then its sign-out** (section 13; the simulation's `all` set, seed 6)
  no longer loses an unsent edit, because nothing leaves at a sign-out: prove that seed.
- The account's identity while signed out: the ledger keeps the account it was signed out of (it does already).
  A device that was never signed in and has items: they stay, and join the first account that signs in (say what
  the code does today and keep it unless it removes something).

**Yours**: core's `Sync/` where the hold and the sign-out are decided (`SyncCore…`, `SyncStatus`, the simulation and
its invariants under `Sync/Testing/`, their tests); in the app `HITList/Services/SyncEngine/SyncEngine.swift`'s
account handling and what it calls for a sign-out, `SyncEngineSettings.swift`'s `SyncEngineWords` for this hold
only (agent 167 edits the switch group in the same file: keep your hunk to the hold's words), their tests. **Not
yours**: `SyncEngineSwitch.swift`, `SyncEngine+Move.swift` (167), `CloudKitTransport.swift` unless the sign-out
cannot be done without it (say why), the mirror's side (`Services/Sync/`, `CloudSyncMonitor`, `AccountSwitch`
beyond the one call the engine makes into it), the models, `dev/`.

Order: the rule as failing tests first (the brain's, then the simulation's invariant: "after a sign-out every item
that was here is here"; "after a sign-in to the same account the device and iCloud agree and nothing made on
either side while signed out is lost"; "after a sign-in to another account nothing of the first account's is in
the second's iCloud"); then the change; then 1,000 histories of each of the eight fault sets and of `all`
(`dev/SYNC-ENGINE.md` section 9 names how they are run), with no failure that is not one of the written limits.
Words: one sentence for the hold, in the engine's plain voice, and the same in the status line; a test pins them.

Nobody talks to iCloud: no probe, no rehearsal, no device. Proof: core's tests whole; the app's `SyncEngine` tests
on the Mac (`-only-testing:HITListTests` for the folder, then the whole of `HITListTests` once at the end). In your
report: the text for `dev/SYNC-ENGINE.md` sections 10, 12 and 13 as it should now read (the supervisor edits the
document), every case you found where a sign-out still removes or hides something, and what a friend on the
**earlier** sync sees at a sign-out today, traced in the code (it is what most testers have until they are moved).
