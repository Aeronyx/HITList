# Brief 78: a bolt with inertia, and a calm answer to a sync blip (session `steady-bolt`, effort xhigh)

George, 2026-11-10, on 0.9.0 (21):

> Also, the new bolt animation is great, but the bolt is still spazzing out a lot and flashing very abruptly before
> syncing; the bold needs to have a bit more inertia in terms of animation. It should only flash when actively trying
> to sync/when it hasn't synced in a significant amount of time; if it's actively syncing, working on connecting, or
> has synced within the past 30 seconds or so and the connection is still good, it shouldn't flash or flicker, even if
> a change is made and synced. The point of the bolt is to visually tell a user "Status is green", not to inform them
> every single time something happens in the background.

> Also, as a sidenote, Build 21 is giving me a Sync error now that I'm messing with it […] However, after 2-3
> minutes, it resolved itself on both iOS and Mac; I just wanted you to be aware.

Read `dev/briefs/COMMON.md` (Round 17 block first), `54-bolt-strike.md` and `68-bolt-slam.md` (the rare "you're good
to go" strike and slam, which George likes and which stay exactly as they are, gate included), then
`HITList/Services/SyncState.swift` (`SyncState.derive`, `SyncConfirmation`, `BoltStrikeGate`),
`HITList/Support/SyncStatusViews.swift` (`SyncBolt`, `SyncBolt.look(for:)`, `SyncIndicatorDot`) and
`HITList/Services/CloudSyncMonitor.swift`.

## Why it flickers today
`SyncBolt` draws the raw state the moment it changes: `bolt.fill` while synced, the hollow `bolt` with a repeating
pulse while syncing, a slashed bolt for offline or an error. CloudKit's mirroring runs an export after every save and
imports whenever a push arrives, each a few hundredths of a second long (the log below has four in three seconds at
launch), so the glyph swaps and pulses every time anything happens. An account blip adds slashed and red frames.

## What George wants (the rules; pin them as a pure function of the raw states over time, with tests)
1. **The bolt says "status is green" and then keeps still.** While the last good sync is recent and nothing has been
   wrong for long, it is the steady filled bolt, whatever is happening underneath: a change saved and exported, an
   import from a push, connecting, a setup, a short error that mends itself. "Recent" starts at George's 30 seconds:
   choose the windows from how the app really syncs (read a day of sync log timings in the tests' fixtures and the
   one below) and say what you chose and why.
2. **It shows work only when work is the news**: a sync that has been trying for a while without finishing (seconds,
   not frames), or the first sync after a long time without one. Then a calm working look, not a flash: decide
   whether that is the hollow bolt, a slow breath of opacity, or both, and make it enter and leave gently.
3. **It shows trouble only when trouble has stayed**: offline, signed out, an error. A state that would turn the
   bolt grey, slashed or red must have lasted long enough to be worth saying (and a state the person must act on,
   such as signed out for good, may show sooner than a network wobble).
4. **Inertia in the drawing itself.** No look changes on a single frame: every change crossfades over a few tenths
   of a second, and a look stays at least a couple of seconds once shown, so it can never flip back and forth.
   Reduce Motion gets the same timing with plain fades.
5. **The same for every other live sync mark**: `SyncIndicatorDot`'s pulse on every finished import or export, the
   profile menu's iCloud line if it flickers, Settings' status row (words may still say "Syncing…" there: it is the
   place to look closely; but it must not strobe either). The rare strike or slam (`BoltStrikeGate`: after launch,
   after a minute away, after a minute of trouble) is unchanged.
6. **A Debug way to see it**: a launch argument that replays a scripted run of raw states at speed (a burst of
   exports, a slow import, an account blip, offline and back), so you can record the bolt before and after and
   George can be shown frame strips. Record both on the Mac and the iPhone simulator.

## The sync blip (look, harden what the app does, do not chase Apple's side)
George's Mac, first launch of build 21 after the TestFlight update, minutes after the Production schema deploy (the
iPhone did the same; both mended themselves in two or three minutes). Times local, paths removed:

```
18:11:17.396  launch    Launch HITList 0.9.0 (21) · macOS · Production · TestFlight
18:11:18.449  event     Setup started
18:11:18.516  event     Setup finished in 0.62 s
18:11:18.565  event     Export started
18:11:18.716  event     Export finished in 0.05 s
18:11:18.732  event     Import started · id=D589BCF1
18:11:25.107  account   CKAccountChanged received
18:11:25.638  account   iCloud account: available → temporarily unavailable
18:11:28.294  event     ERROR Import failed after 9.6 s: iCloud needs you to sign in again · ckError=accountTemporarilyUnavailable · error=CKErrorDomain 36
18:11:28.313  event     Setup started
18:11:28.401  event     Setup failed after 0.09 s: not signed in to iCloud · error=NSCocoaErrorDomain 134400
18:11:29.638  account   CKAccountChanged received
18:11:30.594  account   CKAccountChanged burst ended · notifications=2
18:11:36.959  account   CKAccountChanged received
18:11:39.171  account   CKAccountChanged received
18:11:39.286  event     Setup started / finished in 0.01 s (twice)
18:11:39.456  event     Import started · id=73B6CAE9
18:11:39.757  account   iCloud account: temporarily unavailable → available
18:11:47.113  event     Import finished in 7.7 s
18:11:47.130  event     Export started / finished in 0.01 s
18:11:47.349  event     Import started · id=F5FBC4BD
18:11:47.667  event     ERROR Import failed after 0.44 s: app can't use iCloud · ckError=badContainer · error=CKErrorDomain 5
```

The account going "temporarily unavailable" and a `badContainer` straight after are iCloud's own, most likely the
account's token refreshing around the update and the deploy. What is ours:
- **What the person saw.** For those minutes the status read "Sync paused: iCloud needs you to sign in again" and
  then "Sync paused: app can't use iCloud", which is alarming and was untrue ten seconds later. Under rule 3 a
  blip like this shows nothing unless it lasts; when it does last, the words should say what is known ("iCloud
  isn't answering, HITList will keep trying") and keep the alarming ones for errors that have stayed.
- **What the app did.** Trace this exact sequence through `CloudSyncMonitor`, `AccountWatch`, `Services/Sync/*`
  (`SyncRecovery`, `SyncWatchdog`, `AccountSwitch`) with a test that feeds it: nothing destructive may run on an
  account blip where the account comes back the same (no reset, no "switched account" hygiene, no cleared
  reminders, no profile changes), the app must keep retrying by itself after a `badContainer` or an
  `accountTemporarilyUnavailable` that follows an account-change burst, and the log should end with a note that it
  recovered and how long it took. Fix what the trace finds; if it finds nothing, say so and show the trace.
- Do not add polling, do not restart the container on a hair trigger, and never delete or reset anything to "fix"
  sync (COMMON's rules).

## Ownership
`HITList/Services/SyncState.swift`, `HITList/Support/SyncStatusViews.swift`, `HITList/Services/CloudSyncMonitor.swift`,
`HITList/Services/AccountWatch.swift`, `HITList/Services/Sync/*`, `HITList/Views/Settings/ICloudSettingsGroups.swift`,
`ICloudCheck.swift`, `SyncLogView.swift` and `Mac/LastSyncChange.swift` (words and marks only), their tests
(`SyncStateTests`, `SyncLogTests`, `SyncWatchdogTests`, `AccountSwitchTests`, `AccountWatchTests`, `BoltMotionTests`).
Not yours: `BoltSlamMotion.swift` and the strike's keyframes (unchanged), `ScreenMenu.swift` (the bolt's toolbar
item stays where it is), `ProfileMenu.swift` (brief 75's: if its iCloud line flickers, steady the state it reads
rather than the menu, or give the supervisor the line), the design system and popouts (75), widgets (74: its snapshot writer listens for finished
imports through the existing notification; keep `Notification.Name.cloudKitImportSucceeded` posting as it does),
companions (76), the list views and Settings → General (77), the models and schema, `dev/ROADMAP.md`,
`CHANGELOG.md`, `WhatsNew.swift`.

## Done
Frame strips of the bolt before and after through the scripted run, Mac and iPhone, with the times of every look
change marked. The windows you chose (fresh, working, trouble, minimum dwell, crossfade) in a small table with the
reason for each. The trace of the blip through the code and what you changed. All three suites green.
