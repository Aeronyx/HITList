# Brief 26: Beta-readiness review: the core of HITList must be rock solid

Effort: Max. Model: Opus 5.5. Read `briefs/COMMON.md` first, then this brief, then the code paths named
below before you touch anything.

## Why (George, 2026-11-02)
"I am going to release this app to my friends for beta testing soon, and while UI/UX bugs are to be
expected, the core functionality of adding/completing tasks, cloud sync, sticky drafted tasks, and otherwise
using HITList as a basic, trustworthy todo list must be rock solid." This is the last complete review before
that build. You are reviewing master as it stands after the sync-robustness work (brief 25) was merged.

## What you are reviewing
The core, in order of how badly a bug would hurt a friend who trusts the app with their tasks:
1. **Data safety.** Nothing is ever lost or duplicated: `HITList/Services/TaskActions.swift` (create,
   complete, uncomplete, delete, reschedule), `Deduplicator.swift`, `LocalCacheReset.swift`,
   `ModelContainerFactory.swift` (store location, reset, migration plan `HITListMigrationPlan` and the
   V1→V2 schema), `LocalBackup.swift`/`BackupService.swift`, `SnapshotBuilder.swift`. Every
   `fatalError`, `try!` and force unwrap on a user-data path is a finding.
2. **Adding tasks.** The quick-add card on iPhone (`Views/Popouts/QuickAddPopout.swift`, `PopoutHost.swift`,
   `QuickAddDraft.swift`, `QuickAddEntry.swift`), the Mac panel and inline rows, `HITListCore`'s
   `QuickAddParser`/`DateExpressionParser` (dates, times, priorities, `#group`, `@label`, `every …`,
   `!15mb`), the 500-character title cap (`TaskLimits`), and **sticky drafts** (`QuickAddDraftStore`): the
   text survives tap-away, Discard asks first, backgrounding and relaunch bring it back, adding or
   discarding clears it. Edge cases: whitespace-only titles, emoji, a title that is only a token
   ("tomorrow"), a draft restored into a different list's card, two windows on the Mac.
3. **Completing tasks.** `TaskListView`, `InboxView`, `UpcomingView` with `CompletionAnimator`,
   `CompletionToastState` (undo), recurring tasks (`RecurrenceRule`: completing advances the date and undo
   restores it), completing from the task popout and from a notification action
   (`Services/Notifications/NotificationResponder.swift`), completing the same task twice fast, completing
   while a sync import lands.
4. **Sync.** The merged sync work: `Services/CloudSyncMonitor.swift`, `Services/Sync/` (log, watchdog,
   environment, push delegates), `SyncState`. Does the log record what it claims, does the watchdog fire
   only when it should, is nothing on the hot path slow or chatty, are the app-delegate adaptors correct on
   both platforms, does a local-only launch (no iCloud) behave and say so.
5. **Notifications and reminders.** `NotificationScheduler`, `NotificationPlan`, `MorningSummary`:
   nothing fires for completed or deleted tasks, reschedules after sync imports, permission states handled.
6. **Startup and lifecycle.** `HITListApp.swift`, `ContentView.swift`, `MobileShell.swift`: first launch
   with an empty store, launch after a reset, the seeding path (`SeedIdentity`, sample data never seeded
   into a real store), background/foreground, the app killed mid-edit.

### Known follow-ups left by session 25 (sync), to resolve or report
- `Diagnostics.environment` (About → Copy diagnostics) and `ICloudCheck` still assume "Development (Mac)";
  `SyncEnvironment.current` has the right answer for both platforms. Make them use it.
- Debug runs on the Mac share reminders (`NotificationScheduler`) and the daily backup folder (`LocalBackup`)
  with the TestFlight app (same bundle ID); when the store is not `HITList.store`, both should stand down.
- Reset local cache from a side-store run reopens `HITList-Development.store` because the sandbox drops the
  environment; make sure a Production build's reset can never land on the wrong store.
- The 2-minute "stuck" threshold (`SyncWatchdog`) may wrongly show "Sync paused: stuck" during a very long
  first import on a new device with many tasks. Decide whether first imports get more time.
- A TestFlight build must never be classified as Development by `SyncEnvironment` (that would open an empty
  side store and look like data loss). Re-derive the detection from the exported entitlements and add a
  test for every channel.

Not in scope: visual polish, spacing, animations, themes, Settings layout (George expects UI/UX bugs in the
beta and will collect them himself). Do not restyle anything.

## How to work
- Read first, then write failing tests for every suspected bug before fixing it. The test suites are
  `scripts/test.sh core macos ios`; keep all three green after each commit. Commit after every fix with a
  message that names the bug.
- Fix what is clearly a bug in the core. For anything that is a design decision (behaviour George might
  want either way), do not change it: list it in the report with your recommendation.
- Exercise the real app: the iPhone 17 simulator (`xcodebuild build -destination 'platform=iOS Simulator,name=iPhone 17'`,
  `xcrun simctl install/launch`, a launch-argument demo hook if you need to drive a flow; you cannot tap)
  and the Mac app (`xcodebuild build -destination 'platform=macOS'`, open the product; it syncs with the
  CloudKit Development environment, so use the sync log you now have). Kill the app mid-draft and relaunch.
  Toggle the network. Complete recurring tasks and undo them. Reset the local cache.
- Add tests for every core path that had none; report the before/after counts per suite.

## Files you own
Everything above except `Views/` files other than the popouts and the three list views' completion code,
`Models.swift`/schema (additive-only in Production; a schema change is a finding to report, never a commit),
`scripts/`, `project.yml` and entitlements (report, don't edit), ROADMAP (one row: "Beta-readiness review").

## Report
Findings ranked by severity (data loss, wrong data, crash, stuck sync, wrong notification, cosmetic-but-core),
each with the file and line, the failing test you wrote, and the commit that fixed it or the reason it is
left; the lifecycle and sync scenarios you exercised and what the sync log showed; test counts before and
after; the branch name; the decisions for George; and your one-paragraph answer to "is this trustworthy
enough to hand to friends?".
