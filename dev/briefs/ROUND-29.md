# Round 29: 0.9.12 before its release: a crash, and the engine reviewed (2026-11-15, afternoon)

0.9.12 was prepared on the morning of 2026-11-15 (round 28) and not released. George's message at about 15:35
Eastern, verbatim, with two screenshots of crash feedback from App Store Connect and the crash reports saved in
`crashreports/`:

> I haven't released 0.9.12 or clicked Reset Environment in CloudKit yet as we first need to clean up, ensure that
> my friends won't lose data (or instruct them to export it before they do), and fix some crashing bugs if we
> haven't already; I added screenshots from App Store Connect and put the full crash reports inside /crashreports
> from my friend's crashes. Please fix these bugs then finalize and critically review your new CloudSync engine as
> if you were a lead Apple developer with a focus on efficient simplicity.

No sessions this round: the supervisor alone. The work was one crash read from its log, one question answered from
the code, and one review that had to be held in one head. (`crashreports/` is in `.gitignore`: the files hold a
tester's name and address.)

## The crash

Two reports from one friend's iPhone 17 Pro on iOS 26.5.1: 0.9.3 (24), "tried to click from notification on
lockscreen and it crashed", 0.4 s after a cold launch; 0.9.9 (27), "tried to click notification from notification
center", in an app that had been running for ten hours. Both are the same abort:

```
-[NSAssertionHandler handleFailureInMethod:…]
-[UIApplication _performBlockAfterCATransactionCommitSynchronizes:]
-[UIApplication _updateSnapshotAndStateRestorationWithAction:windowScene:]
@objc closure #1 in NotificationResponder.userNotificationCenter(_:didReceive:)
completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*)
```

on a thread that is not the main one. `NotificationResponder` implemented the delegate's `async` forms. For those
the compiler makes the Objective-C method, runs the Swift body in a task, and calls the system's completion handler
from wherever that task ends. UIKit's handler for a notification response updates the app's snapshot and asserts
the main thread; iOS 26 aborts. So every reminder tapped, completed or snoozed could crash the app, since the
delegate was written.

Fixed: both delegate methods are the completion-handler forms and call the handler on the main thread by hand
(`NotificationResponder.respond`). The push handler in `SyncAppDelegate` already did. No other Objective-C delegate
in the app has a completion handler. Tests: the handler is called on the main thread when the delegate is called
from a background one; a tap still asks the shell to open its task.

Not reproduced: the simulators on this Mac are iOS 27, and a Debug build never installs the reminders' delegate
(it opens a side store and stands down from reminders). The release notes say so.

## Friends' data

- **Resetting CloudKit Development cannot touch a tester's data.** TestFlight builds use the Production
  environment; Development holds only what Debug builds on this Mac put there (side stores' test data, the probe's
  records, zone `HITList-e2e1`). Production cannot be reset from the console at all.
- **Updating to 0.9.12 changes nothing about how a device syncs.** Every file outside the engine that changed since
  0.9.11 was read as a diff: with the engine off, the launch makes no engine object, no ledger and no observer; the
  monitor's engine branch is behind `isOnEngine`; the widget and import paths ask an engine that is nil.
- **A released build could have been switched on by a stored preference** (a key in the App Group's defaults,
  written only by a move that no released build offers). Now it cannot: `SyncEngineSwitch.isAvailable` answers no in
  every build that is not a Debug build, before any preference or argument is looked at, and a test pins it.
- Every device already writes a backup once a day (Settings → iCloud & data → Backups; the newest are kept), and
  Settings → iCloud & data → Export JSON… saves a copy wherever the person chooses. Nothing needs exporting for
  0.9.12; before a device ever moves to the engine, it should.

## The review

Read again with George's sentence, the engine's weakest idea was its second paragraph: "Nothing is journalled. The
engine compares." For changes that is a strength. For deletions it meant that an item iCloud held and the device
did not was "deleted here", and everything that followed from that was a guard against it: a hold for "many gone at
once" with numbers (ten items and half of what iCloud holds), a question to the person, a moment remembered for the
markers, a vouch the app had to give before every bulk delete (two call sites, and every future one), a third way
out ("download them again"), a store that had to be strict about cascades, and the review's finding 19. A store
that read empty was one comparison away from emptying every device.

**What changed.** A deletion is known only when the store wrote it down as it was saved. The app watches
`ModelContext.willSave`, where a row about to be deleted can still say its `id`, takes down its key (and a task's
sub-tasks, which the store takes with it) in the ledger's own file before the save commits (`SyncDeletionLog`),
and the save's hint names the rows. The brain notes them (`SyncLocalStore.deletions`, `deletedHereAt`) before it
compares or settles anything, held or not. An item iCloud holds that is not here with no deletion written down is
**missing** (rule M14): its ledger entry is forgotten, every record is asked for again, and iCloud's comes back.
Gone with it: `SyncHold.massDeletion`, `SyncCore.Limits`, `confirmDeletions`, `vouchForDeletions`,
`restoreFromICloud`, their facts in the ledger, the Settings rows and words, the demo state, the vouch calls in
the Todoist importer and the Switchboard rules.

**Also done.**
- A deleting save no longer asks for a read of the whole store (it could not name its rows before), and a whole
  compare no longer runs at the end of every fetch (every push from another device read every row). One runs at a
  launch, when the app comes forward, and when the first whole fetch ends.
- Records that pointed at a deleted item are looked at with it (the store took their reference off; they must wait
  for it before anything of them is sent), whether or not a hint names them. Found by the rig within the hour.
- Finding 18: a record that could not be written because the person had its item open and unsaved is kept and
  settled again when the save comes, when everything is compared, and when the next fetch ends.
- A send whose answer never came (the network dropped, the app died) is remembered until it is answered, in the
  ledger too, for every record and not only new ones; when iCloud's record arrives, each field whose value is the
  one this device sent is taken as agreed. Before, a task un-completed just after its completion was sent
  completed itself again. The remembered sends are read once at a start instead of key by key in every settle.
- An item deleted before the device and iCloud ever agreed on it (a first sync, a save whose answer was lost) is
  now deleted in iCloud too; it used to come back.
- The rig, the pretend iCloud and the in-memory store (3,000 lines) compile into Debug builds only.
- Dead code out (`sendOrder`, an unused parameter).

**Named and not done** (`dev/SYNC-ENGINE.md` section 13 has them with the reasons): one recovery path instead of a
flag per half-failed step; a simpler rule for sub-tasks under a deleted task; the main-thread cost of a first sync
on a phone; the ledger's copy of every record; the monitor's engine branch; SwiftData's own history as the record
of a deletion (it needs a change to the models, so it waits for the release that switches the engine on).

## Proof

- Core: 1,045 tests. New: `SyncCoreDeletionTests` (a deletion written down goes; absence deletes nothing and the
  item comes back; a store that reads empty; a deletion while held; a note that could not be written is told
  again; a deletion before the two ever agreed), `SyncCoreLostAnswerTests`.
- The app, on real SwiftData: the observer takes down a deleted row, and a task's sub-tasks at any depth, before
  the save; the engine's own deletions are never taken down; the notes live in the ledger's file and go with it;
  two hosted devices: a bulk deletion simply goes; rows deleted while nothing watched come back and nothing is
  deleted in iCloud.
- The rig: a new fault, a store that loses rows, as a set of its own. 5,000 histories of 300 steps on three devices
  across eight fault sets. Seed for seed against the engine before the review: no finding it did not have; four of
  its failing seeds pass.
- In the running app: two Debug Mac apps on side stores on a pretend iCloud. One sent its ten records; the other,
  empty, showed them; a task deleted with its sub-task in the first, through the editor's menu, left the second
  ("deleted here; its marker is waiting to go" twice, then "M9 deletedThere: deleted here" twice).
- Not run again: the engine against CloudKit (the transport did not change).

## Cleaning up

- Three of the five agent worktrees of round 28 removed (merged, clean); two are held by the app and go when it
  lets them. 72 older session worktrees remain, about 105 GB, every branch merged and every tree clean: George was
  asked.
- For George: CloudKit Console → `iCloud.com.trammells.hitlist` → Development → Reset Environment…; the side
  stores in the App Group's folder (`HITList-sup28*`, `HITList-e2e*`, `HITList-s14*`, `HITList-r29*`, their
  `.ledger` files, `SyncEnginePretend-*`), never `HITList.store`.
