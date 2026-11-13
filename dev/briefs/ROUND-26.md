# Round 26: 0.9.10, sync back to what CloudKit's mirror reports (2026-11-13, midday)

0.9.9 was released on 2026-11-12 (build 27). George's message at about 12:30 Eastern the next day, verbatim:

> Something isn't right; HITList is idling at over 24% CPU usage on my Mac, and it's not even able to sync while
> doing so. It's been stuck on the hollow bolt with no error for 5 minutes now, and just says "Sending 3 changes to
> iCloud..." while the "Last change..." is constantly flickering back and forth between "Export from iCloud - just
> now" and "Import from iCloud - just now". I'm really surprised that, after so many iterations on a simple iCloud
> sync, we're still unable to even get close to a working product. Why is this so hard for us? How do other apps
> like Todoist handle cloud sync so cleanly? Even my friend making a simpler app has better cloud sync than us.
> Where are we going wrong? Did we overcomplicate something or misimplement something? I find it hard to believe
> there isn't extensive documentation/best practices on how to best use iCloud Sync, yet we seem to be constantly
> failing at every turn; we're simultaneously sucking up way too much performance and it isn't even working
> properly. I need you to act like a professional Apple App Developer and write a robust, lightweight cloud sync
> foundation for HITList.

No sessions this round: the supervisor did it alone, in one sitting, because the work was one diagnosis and one
design that had to be held in one head.

## What was found, in the running app
The app was still running when the message arrived (0.9.9 (27), pid 45946, launched 12:25:11, 18.5% CPU), so it was
looked at before anything was read: an 8-second `sample`, symbolicated with the release archive's dSYM, and the
app's own log lines from `/usr/bin/log`. Nothing of George's was opened, stopped or changed.

1. **Sync was working.** The mirror's setup took 0.82 s; every import (0.15 to 0.47 s) and every export (0.01 to
   0.25 s) of the session finished well. Not one error.
2. **The hollow bolt came from HITList's own checking layer** (brief 95, 0.9.4: `SyncBeat`, `BoltTruth`,
   `ICloudZoneIndex`, `SyncComparison` in the loop). A second CloudKit client inside the app asked iCloud every 15 s
   while a window could be seen, kept its own copy of the zone's record index, compared it with the store record by
   record, and held the bolt hollow whenever they differed. At 12:25:13 it logged "This device and iCloud differ (3
   only here)": two filters and a label created on 2026-10-26, last changed 10-29 and 10-31, that iCloud doesn't
   hold. It worded that "Sending 3 changes to iCloud…". Nothing was being sent: the mirror had nothing queued, and
   those three would have sat there for good. After two minutes the words became "This device and iCloud differ",
   and each time the window was shown again the two minutes started over.
3. **The CPU went to the hollow bolt's "breath"**: `BoltBreath`, a `phaseAnimator` with no end. The sample's main
   thread spent about a fifth of its time in `NSToolbarItemViewer` layout → `NSHostingView.layout` → SwiftUI's
   render, with `BoltSlamMotion.Warp.effectValue` and `ScreenChrome.boltAndPill` the only frames of ours in it. In
   the Mac's toolbar every frame of an animation lays the toolbar out again. It ran with the window covered too.
4. **"Last change" flipped because the mirror does**: it imports and then exports each time the app comes to the
   front (nine times in eight minutes while George went between HITList and this chat), and the row named only
   the newer of the two.

Why those three records are only on the Mac is not known and cannot be told from outside the store. Check iCloud…
names them and offers both repairs.

## What was decided
- **Keep Apple's engine.** SwiftData's CloudKit mirror is the supported path, it is configured the way the
  documentation asks (one process mirrors the store, optional or defaulted fields, schema deployed before release),
  and it works. A rewrite on `CKSyncEngine` would give HITList the queue of pending changes as a real thing, and
  would cost a new record schema in Production, a migration of every tester's data, and months of the risk this
  round is trying to end. Not without George's word.
- **Say only what the engine says.** The mirror reports each setup, import and export with its start, end and
  error. That is all HITList knows, so it is all the marks say: `SyncSessionGate` (hollow from a launch until the
  session's first import; filled after it while nothing fails; a minute of silence says so).
- **George's rule of 2026-11-11 is retired**: "The bolt should never, ever display as full/filled in unless it
  actually successfully synced within the last real-time 30 seconds." An idle app has nothing to sync, so the rule
  could only be kept by asking iCloud over and over and comparing; that is the layer that failed here. What stands
  in its place: the bolt is never filled before this launch has fetched from iCloud, never filled while anything
  has failed since, and its words name the time of the last import or export. His to reverse.
- **Nothing at rest.** No request the mirror didn't make, no timer with nothing pending, no animation without an end.
- **The comparison stays, on request**: Settings → iCloud → Check iCloud… and its two repairs.

## What changed
- New: `Services/Sync/SyncSessionGate.swift` (pure, about 100 lines) and `SyncSessionGateTests`.
- Gone: `SyncBeat.swift` (with `MacWindowVisibility`), `BoltTruth.swift`, their three test files, the index file in
  Application Support (removed once at launch), `sync.lastConfirmedAt`.
- `CloudSyncMonitor`: the beats, the truth, the inventory and the comparison out; the gate in. About 290 lines fewer.
- `SyncWords`, `SyncHealth`: "Synced 3 min ago" / "Last synced 3 min ago, checking…"; no "Sending N changes".
- `SyncStatusViews`: the bolt stands still (`BoltBreath` gone); Settings' line ticks every 30 s, not every second.
- `LastSyncChange`: "Received 3 min ago · Sent just now", both at once.
- `SyncAudit`, `ICloudZoneReader`, `ICloudZoneIndex`: for Check iCloud… only, nothing kept between launches;
  `SyncBeatFailure` is `ICloudReadFailure`.
- Unchanged: the mirror and the store, the schema, pushes, `SyncWatchdog`, `SyncSteadiness`, `SyncLog`,
  `SyncRecovery`, the strike gate, Check iCloud…'s screen.
