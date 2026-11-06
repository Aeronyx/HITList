# Brief 25: iCloud sync that is profoundly robust and lightweight, with the data to prove it

Effort: Max. Model: Opus 5.5. Read `briefs/COMMON.md` first (its "Environment" section records the
CloudKit pitfalls that cost hours: `/usr/bin/log`, linking CloudKit explicitly, the ANSCKEVENT table, the
team-prefixed Mac app group, Development vs Production environments), then `HITList/Services/CloudSyncMonitor.swift`,
`HITList/Services/SyncState.swift`, `HITList/Services/AccountWatch.swift`, `HITList/Models/ModelContainerFactory.swift`,
`HITList/HITListApp.swift`, `HITList/Views/Settings/ICloudSettingsGroups.swift`, `HITList/Views/Settings/Mac/LastSyncChange.swift`,
`HITList/Support/SyncStatusViews.swift` (the `SyncBolt`), the two entitlements files and `project.yml`,
and `HITListTests/SyncStateTests.swift`.

## Why (George, 2026-11-02)
"Already ran into a syncing issue on the MacBook app. I need the cloud syncing on this app to be incredibly,
profoundly robust and lightweight, such that it works in almost any environment. Do whatever you need to do to
resolve the current bugs and collect data to solve future ones; create error logs if syncs don't happen within
5 seconds, run tests, etc. Any task I add on the mobile app should appear reliably and without delay on the
desktop app and vice versa." The issue itself was not described, so the first deliverable is the instrument
that will describe the next one, and the second is removing every cause you can find or provoke.

## How sync works today
SwiftData with `ModelConfiguration(cloudKitDatabase: .private("iCloud.com.trammells.hitlist"))`, i.e.
`NSPersistentCloudKitContainer` underneath; the store lives in the app group container (`ModelContainerFactory`).
`CloudSyncMonitor` (a singleton started in `HITListApp.init`) listens to
`NSPersistentCloudKitContainer.eventChangedNotification`, `CKAccountChanged` and `NWPathMonitor`, keeps the
last import/export times in app-group defaults, and derives `SyncState` for the bolt and Settings. There is no
app delegate: nothing logs remote-notification registration or the pushes CloudKit sends, and nothing
notices when a local save is not followed by an export, or a push by an import. The Mac app is sandboxed
(`com.apple.security.network.client`, `aps-environment`). Debug/Xcode builds run against the CloudKit
Development environment; TestFlight builds (iPhone and Mac, `scripts/release.sh`) against Production, so a
Mac run from Xcode never sees the phone's TestFlight data. `Deduplicator` runs after imports (duplicate
seeded rows). Unit tests run hosted in the app against an in-memory store with CloudKit off.

## Files you own
`HITList/Services/CloudSyncMonitor.swift`, `SyncState.swift`, `AccountWatch.swift`, new files under
`HITList/Services/Sync/` (log, watchdog, environment, push delegate), `HITList/HITListApp.swift` (only to
add the app-delegate adaptors and scene-phase hooks sync needs), `HITList/Views/Settings/ICloudSettingsGroups.swift`,
new `HITList/Views/Settings/SyncLogView.swift`, the `.iCloud` case of `MacSettingsSectionContent` in
`HITList/Views/Settings/Mac/MacSettingsPage.swift` (nothing else in that file), `project.yml` and the
entitlements only if a sync-related key is missing (say so in the report; never add
`com.apple.developer.icloud-container-development-container-identifiers`), `HITListTests/SyncStateTests.swift`,
new `HITListTests/SyncLogTests.swift` and `SyncWatchdogTests.swift`, and one ROADMAP row. Not yours: the
model files (`Models.swift`, schema; Production's schema is additive-only and you must not change it), the
bolt's drawing in `SyncStatusViews.swift` (you may add a tap target or state it reads), anything under
`Views/` not named above (Fable is changing the lists and popouts this round).

## Task, in commits (commit after every item)
1. **`SyncLog`: the record.** A persistent, bounded log in the app group container (JSON lines or a small
   SQLite table; cap it at a few thousand entries and a few MB, oldest dropped) of everything sync-related,
   each entry timestamped with a kind and a short message plus structured fields: container events (setup,
   import, export; start, end, duration, success, full error domain/code/userInfo including
   `CKRetryAfter`), account status changes, reachability changes, scene phase changes, app launch (version,
   build, platform, OS, CloudKit environment, store path, store size), local saves (object counts, from
   `ModelContext.didSave` or the Core Data save notification), remote-notification registration (success,
   failure), each push received and how long until the matching import finished, and the watchdog's findings
   (item 3). Mirror every entry to `os.Logger` (subsystem `com.trammells.hitlist`, category `sync`) so
   `/usr/bin/log` shows the same story. Pure, testable core (`SyncLog` with an injectable clock and store
   URL); `CloudSyncMonitor` feeds it.
2. **Push path, both platforms.** Add `UIApplicationDelegateAdaptor` / `NSApplicationDelegateAdaptor`
   delegates that log `didRegisterForRemoteNotifications`, `didFailToRegister` and every
   `didReceiveRemoteNotification` (CloudKit's `CKNotification` fields: subscription, zone, container
   environment). Confirm the container actually registers for pushes on macOS and iOS (check the log on a
   real launch; if it does not, register in the delegate and say why). Confirm the iOS
   `remote-notification` background mode and the `aps-environment` entitlement are present and that
   `scripts/release.sh`'s export produces `production` for both (read the exported app's embedded
   entitlements with `codesign -d --entitlements :-`).
3. **`SyncWatchdog`: the 5-second rule.** A pure state machine (tests!) fed by the log's events: after a
   local save, an export must finish within 5 s or it records `exportOverdue` with the context (online?,
   account status, in-flight events, last error, time since last export); after a push, an import must
   finish within 5 s or `importOverdue`; an event that starts and never ends within 60 s records `eventStuck`.
   Overdue entries are errors in the log and in `os.Logger`. When the overdue export or import later
   completes, record how late it was, so the data says "slow" versus "never".
4. **Environment and build in the open.** `SyncEnvironment`: the CloudKit environment this binary runs
   against (read the embedded entitlement: `SecTaskCopyValueForEntitlement` on macOS, parse
   `embedded.mobileprovision` on iOS; fall back to "unknown") and the distribution channel (Debug, TestFlight
   via the sandbox receipt, App Store). Show both in Settings → iCloud on both platforms ("Production ·
   TestFlight build 11") and in the log's launch entry, with one line of explanation when a device could be
   on the other environment ("A Mac run from Xcode syncs with Development; TestFlight builds sync with
   Production, so the two don't see each other").
5. **Settings → iCloud → Sync log** (`SyncLogView`, iPhone sheet and the Mac page's iCloud section): the
   entries newest first in Inter (`HITType`), errors in `HITColor.danger`, a filter (All / Errors), and
   "Copy log" (text on the pasteboard) plus "Share…" (iOS share sheet) / "Save…" (Mac save panel) of the
   full text. Design-system components only (`HITButtonStyle`, `HITChip`, `slateSheet()`; never system
   default buttons). Also "Last change" (`LastSyncChange`) stays.
6. **Fix what you find.** Run the Mac app (dev-signed, your Mac is signed in to iCloud) and watch the log
   while you add, edit and complete tasks; run the iPhone simulator too (it has no iCloud account, so it
   shows the local-only path; make sure that path logs cleanly and the bolt says so). Provoke failures:
   network off (toggle Wi-Fi via `networksetup -setairportpower` if allowed, otherwise the simulator's
   network link conditioner is off-limits, so say so), app backgrounded, two Mac instances, a store reset.
   Every cause of a missed or late sync that you can see in the log gets a fix or a documented reason.
   Candidates to check: the container not registering for pushes on macOS; imports only on push with no
   catch-up when the app becomes active (on `scenePhase == .active` and on wake, re-check the account and log
   whether an import follows; if SwiftData offers no way to ask for one, record that and the measured delay);
   the Mac sandbox denying cloudd (CKError 6; COMMON's note); `CKRetryAfter` back-offs; account changes.
   Keep it lightweight: no polling loops tighter than a minute, nothing that keeps the radio on.
7. **Tests.** `SyncLogTests` (bounded size, ordering, round trip, text export), `SyncWatchdogTests` (the
   5 s rule, late completion, stuck events, no false positives when offline is already known),
   `SyncStateTests` green, `SyncEnvironment` parsing with sample entitlement plists. `scripts/test.sh core
   macos` after each commit, `ios` before the last.
8. **ROADMAP.** One row: "Sync robustness: log, watchdog, environment, push diagnostics" with what you
   verified and what remains.

## Report
What changed per commit; the log of your own Mac session (the interesting lines); every cause found and
whether it is fixed; the entitlement check results; test counts; the branch name; and the questions only
George can answer (for example which device and what he saw when "the syncing issue" happened).
