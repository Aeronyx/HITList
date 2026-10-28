# Brief: ROADMAP item 6, Reminder robustness

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first.

## Files you own
`HITList/Services/NotificationScheduler.swift`, new files under `HITList/Services/Notifications/`,
new test files in `HITListTests/`. In `HITList/HITListApp.swift` you may add exactly ONE line,
`NotificationScheduler.bootstrap(container: container)`, at the end of `init()`; change nothing else
there (another session owns that file). Do not touch `SettingsView.swift`, `project.yml`, or any model.

## Problem
`NotificationScheduler.reschedule` runs only when the scene becomes active, so a task added or
rescheduled on the Mac never fires on the iPhone until the iPhone app is opened. Notifications have
no actions, ignore time-zone changes, and the 64 pending-request cap is only respected by accident.

## Task, four commits
1. **Bootstrap and triggers.** Add `NotificationScheduler.bootstrap(container:)`: sets the
   `UNUserNotificationCenter` delegate, registers the category, and installs observers so
   `reschedule` also runs (debounced 2 s via `Debouncer`) after `.cloudKitImportSucceeded`, on
   `NSSystemTimeZoneDidChange`, on `.NSCalendarDayChanged`, and on the platform's significant-time
   change (`UIApplication.significantTimeChangeNotification` on iOS; day-changed on macOS). The app
   has the `remote-notification` background mode, so CloudKit pushes wake it and the import hook fires
   in the background; make sure the reschedule path has no main-thread UI dependency. Keep the existing
   scene-activation call working.
2. **Actions.** Category `TASK_DUE` with actions Complete (calls `TaskActions.toggleCompletion`,
   which already rolls recurring tasks forward) and Snooze 1 hour (`TaskActions.reschedule` to
   now + 1 h, keepTime true). Handle them in the delegate on the main actor using a `ModelContext` on
   the container; after handling, reschedule. Foreground presentation: show banner + sound while the
   app is active (`.banner, .sound`). Tapping the notification body should post
   `Notification.Name("HITList.openTask")` with the task id in userInfo so a later UI change can deep
   link; do not implement the UI side.
3. **Cap and content.** Sort candidates by due date and schedule at most 60 (leave headroom under
   iOS's 64 cap); if truncated, schedule one extra summary notification at the first dropped due time
   saying "N more tasks due later today". Diff instead of wiping: compute the desired request set,
   remove only stale identifiers, add only new/changed ones (identifier = task id; include a content
   hash in userInfo to detect changes), so the system never briefly has zero requests. Body shows
   project · priority as today, plus "overdue" wording if already past. Respect `isEnabled` and
   authorization status; if authorization was denied, log once under category "notifications".
4. **Tests.** Pure planning function `NotificationPlan.make(tasks:now:limit:)` in a new file returning
   the identifiers, trigger dates and bodies; test the cap, ordering, summary insertion, horizon,
   excluded completed/untimed tasks, and the diff (added/removed/changed) against a fake pending set.
   Also test that Snooze lands exactly one hour later and preserves the time flag.

## Verify
Simulator: build signed, enable Reminders in Settings, create a task due in 2 minutes with a time,
background the app, confirm the notification arrives and that Complete/Snooze actions work from the
notification. Mac: same with a Release build; also check `/usr/bin/log` shows a reschedule after a
CloudKit import. Update the ROADMAP.md item 6 row to "done <date>". Report per COMMON.md.
