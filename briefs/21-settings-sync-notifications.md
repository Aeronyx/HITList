# Brief 21: Settings v2, sync confirmation, notification test and integrations

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first (especially "Where things stand" and
"Round 4 ownership"), then `HITList/Views/SettingsView.swift`, `HITList/Support/Preferences.swift`,
`HITList/Support/AppInfo.swift`, `HITList/Support/SyncStatusViews.swift`, `HITList/Services/CloudSyncMonitor.swift`,
`HITList/Services/SyncState.swift`, `HITList/Services/NotificationScheduler.swift` and
`HITList/Services/Notifications/*`. Build only on the design system (`HITList/Support/DesignSystem/README.md`).

## Why (George, 2026-10-31, after using build 5)
"Let's add versioned releases with preflight tests and a release version number visible in the settings
[done by Fable: `AppInfo`, the About group, `release.sh --version`]. We should also begin to implement more
settings, notification tests/integrations, cloud sync confirmations with a very small visual indicator,
and more."

## Files you own
`HITList/Views/SettingsView.swift`, new files under `HITList/Views/Settings/` **except**
`AppearanceSettingsSection.swift` (session 22's; keep the call to it where it is), `HITList/Support/SyncStatusViews.swift`,
`HITList/Services/CloudSyncMonitor.swift`, `HITList/Services/SyncState.swift`, `HITList/Services/NotificationScheduler.swift`,
`HITList/Services/Notifications/*`, `HITList/Support/AppInfo.swift`, their tests (`SyncStateTests`,
`NotificationPlanTests`, `NotificationActionTests`, `AppInfoTests`, new `SettingsTests`), and the ROADMAP row
named below. Add preference keys in a new `HITList/Views/Settings/SettingsPreferences.swift` as
`extension Preferences`; never edit `Preferences.swift` itself (sessions 20 and 22 read it).
Not yours: `MobileShell`/`Tabs/*` (session 20 reads `Preferences.startTab`), `Theme.swift`, `HITTokens.swift`,
`Models.swift`, `project.yml`, `HITListApp.swift`.

## Know before you start
- `SyncIndicatorDot` is the 6 pt dot session 20 places on the "…" button of every iPhone screen. You own
  its behaviour; it must stay 6 pt and keep its three colours (green synced, grey syncing/offline, orange
  attention).
- `CloudSyncMonitor` records `NSPersistentCloudKitContainer.Event`s (`record(_:)`), exposes
  `lastImportAt`, `lastExportAt`, `state`, `accountStatus`, `isOnline`. `SyncState.derive(...)` is pure and
  tested. CloudKit mirroring cannot be forced; there is no "sync now".
- Notifications: `NotificationScheduler.isEnabled`, `requestPermission()`, `reschedule(context:reason:)`;
  `NotificationPlan` (pure, tested) turns tasks into requests, firing at due − `reminderOffsetMinutes`.
  Categories and actions live in `NotificationResponder`.
- Settings is a sheet on iPhone (`HITSheetChrome`) and the Settings scene on the Mac; both show the same
  `groups`. The About group shows `AppInfo.versionLabel` ("0.2.0 (6)").
- The Mac CloudKit environment is Development; the iPhone's TestFlight build is Production. A record
  count across devices therefore differs between the two; say so in any UI that shows one.

## Task, in commits
1. **Sync confirmation.** When `lastExportAt` or `lastImportAt` advances, `SyncIndicatorDot` confirms it:
   a single quick pulse (scale 1 → 1.6 → 1 with `HITMotion.spring`, or a brief brighter ring), no repeat,
   none under Reduce Motion. The Settings iCloud group gets a "Synced just now" line that animates a
   checkmark in once (`contentTransition(.symbolEffect(.replace))`) and then shows "Synced 2 min ago" as
   today. Add `CloudSyncMonitor.lastChangeAt` (or equivalent) and test the derivation.
2. **Verify sync.** An "Check iCloud…" row in the iCloud group performs a real round trip and reports in
   one line under the row: account status, container reachability (`CKContainer.fetchUserRecordID` or
   `privateCloudDatabase.fetchAllRecordZones`), whether the CloudKit zone `com.apple.coredata.cloudkit.zone`
   exists, and how long the check took. Errors are shown in plain words. Mac note: "Development
   environment on the Mac" so the number isn't compared with the phone.
3. **Notification test.** Reminders group: an "Authorization" row (Allowed / Denied / Not asked /
   Provisional, from `UNUserNotificationCenter.notificationSettings()`), an "Open system settings" row
   (iOS: `UIApplication.openNotificationSettingsURLString`; Mac:
   `x-apple.systempreferences:com.apple.Notifications-Settings.extension`), a "Scheduled" row with the
   pending request count and the next fire time, and "Send a test notification" which schedules one five
   seconds out using the app's own reminder category (so its actions appear) and tells George to lock the
   phone. Add a `NotificationScheduler.sendTest()` and a pending-summary function; unit-test the summary.
4. **Default reminder offset.** Reminders group: "Default reminder" picker (At due time / 5 / 10 / 15 /
   30 min before / 1 hr before) stored at `Preferences.defaultReminderOffsetMinutes`. `NotificationPlan`
   applies it to timed tasks whose `reminderOffsetMinutes` is nil; a task's own `!` offset wins. Tests.
5. **Daily summary (integration).** Reminders group: "Morning summary" toggle with a time (default 8:00):
   one local notification per day, content computed at reschedule time ("5 tasks today, 2 overdue · first:
   Haircut 11:00"), category `summary`, tapping it opens the app on Today (reuse the responder's routing;
   on iPhone that is just opening the app). Skip the notification when nothing is due. `NotificationPlan`
   grows a pure `summaryRequest(tasks:at:now:)`; tests.
6. **More settings.** New `GeneralSettingsSection`: "Start screen" (iPhone only: Inbox / Today / Upcoming /
   Browse → `Preferences.startTab`), "Week starts on" (Sunday / Monday / System → used by `DateExpressionParser`'s
   `startOfWeek` if it has a hook; if not, store the key and list it in your report as pending), "Show
   task count on the app icon" (badge = overdue + today count, set in `NotificationScheduler.reschedule`;
   needs `UNAuthorizationOptions.badge`, already requested or add it), "Confirm before deleting" (store
   the key; the delete paths belong to others, list as pending). Move the Reset-cache row to the end of the
   iCloud group under a "Danger" footer.
7. **About.** Below Version: "Copy diagnostics" (version, build, OS, device model, sync state, last import/
   export, store path, notification authorization) to the pasteboard; "What's new" opening a sheet that
   shows a short hand-written list for the current version (a static `WhatsNew.entries` array you keep in
   `Views/Settings/WhatsNew.swift`; add this round's items).
8. **Tests** (`SettingsTests` + the existing files): the sync pulse trigger, the Check-iCloud result
   formatting, the pending-summary text, default offset precedence, the morning summary content and its
   skip rule, start-screen default. Run `scripts/test.sh core macos` before each commit, `ios` before
   the last one.
9. **ROADMAP.** Add one row to the second table: "Settings v2 (sync confirmation and check, notification
   test, default offset, morning summary, start screen, diagnostics, What's new)" with status and what you
   verified.

## Verify running
iPhone 17 simulator: Settings from the Browse tab (session 20 adds the "…" route; Browse's Settings row
exists today), the test notification arriving on the lock screen (`xcrun simctl` cannot lock; background
the app with the Home gesture), the morning summary scheduled (print the pending requests), the sync dot
pulsing after an edit on the Mac build (the Mac uses Development CloudKit; the simulator is signed-in-less,
so the pulse is easiest to see on the Mac: run the Mac app, edit a task, watch the dot in the Mac sidebar's
footer area if you also place it there, or log the pulse). Record what you saw.

## Report
What changed per commit; test counts before and after; which of the new settings are wired end to end and
which store a key for another file to read (list the file); the branch name; anything George must do
(for example allowing notifications again if the authorization options changed).
