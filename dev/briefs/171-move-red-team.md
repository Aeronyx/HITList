# 171: try to lose a tester's tasks with the move (a review; no code)

The next build moves every tester's device from Apple's mirror to HITList's own sync engine, by itself. George,
2026-11-18: "Before release, tell me clearly that both internal and external testers will safely retain their task
data after the move, or if I should tell them to download everything first." The supervisor has to answer that in
one sentence and be right. **Your work is to make that sentence false if it can be made false**: find every way a
person's tasks, Groups, labels, filters, switches, boards, profile, reminders or what they typed could be lost,
hidden, doubled, brought back after deletion, or overwritten by an older copy, during and after the move.

**Read-only**: change no file, build nothing in the main checkout (run tests in your own worktree if you want to
prove a sequence: a failing test you wrote is the best finding there is; put it in your report, not in a commit).
Read `dev/SYNC-ENGINE.md` whole (sections 7, 8, 10, 11, 13, 14 twice), `dev/briefs/ROUND-33.md`, then the code:
`SyncEngineAutoMove.swift`, `SyncEngineSwitch.swift`, `SyncEngine+Move.swift`, `SyncEngine.swift` (launch and first
sync), core's `SyncCore` (the first fetch with an empty ledger: section 7's "merge without a memory"),
`RecordMerge`, `SwiftDataSyncStore`, `Deduplicator.mergeSharedIDs`, `LocalBackup`, `SyncRepair`, `LocalCacheReset`,
`ModelContainerFactory` (the store's opening, the set-aside), `AccountSwitch`.

**What is about to change, so review the design as well as the code** (the supervisor is building these now):
(a) a device moves only after George's word, a record in iCloud's public database (brief 170); (b) "the mirror's
bolt is filled" becomes "the mirror has caught up in this launch" (filled, or its comparison ran and found
differences), and a device whose mirror never catches up moves anyway after seven days and three launches;
(c) the move no longer waits for the person to reopen the app: an iPhone or iPad ends its own process once it is
in the background after the move is written, so the next opening is on the engine, and a Mac relaunches itself
when it is not the active app and no card is open; (d) the backup made before the move is kept beside the daily
ones under a name the rotation does not remove.

**Walk each of these people through it, step by step, with the code open**, and say what each ends with:
1. One iPhone, a few hundred tasks, the mirror healthy.
2. One iPhone whose mirror's comparison has differed for weeks (records in iCloud the device never took, or the
   reverse).
3. An iPhone and a Mac, both updated the same hour; then the same with the Mac updated nine days later while
   the person kept using both (edits, completions and deletions on each side in between).
4. Three devices, one of them an iPad opened once a month and still on 0.9.13.
5. A person who deletes the app and installs it again a week after moving (one device; then with a second device
   that never moved).
6. A new phone restored from an iCloud device backup made before the move; and one made after it (what do the App
   Group's defaults, the store file and the ledger file say after a restore, and are they of one moment?).
7. A person signed out of iCloud at the update, who signs in a week later; one whose iCloud storage is full; one
   with iCloud Drive off for HITList; one on a managed device where CloudKit answers "restricted".
8. A person with 6,000 tasks imported from Todoist: the first send (how many requests, what happens when iCloud
   answers "slow down" or the app is closed half way), and the second device's first fetch.
9. The app killed, the phone restarted or the battery dead at each line of the move, and between the move's
   preference and the first launch on the engine, and half way through the first send.
10. A person who uses Shared Tasks, widgets that complete tasks, Siri or Shortcuts, the share extension, Claude's
    connector on the Mac, at each moment above.
11. The way back, by hand, after the move the app made: one device, then two.
12. Two people on one iCloud account; one person with two iCloud accounts on two devices.

**A finding**: numbered; **A** (data lost, hidden, doubled, overwritten, or a device left that no longer syncs and
does not say so), **B** (the person is told something untrue or left without knowing what to do), **C**; the steps
as a person and their devices take them; where (`path:line`); how sure (**certain**: traced or run; **likely**; **to
check**); the smallest fix; and **whether an export beforehand would have saved them**. Then, at the end, the
sentence itself as you would let the supervisor say it to George, with every condition it needs, and the list of
what a tester should be told before the update. No padding and no praise: what holds, leave out.
