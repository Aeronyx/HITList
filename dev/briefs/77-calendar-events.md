# Brief 77: calendar events beside the tasks (session `calendar-events`, effort high)

George, 2026-11-10, starting 0.9.1:

> … along with any other crucial steps from the roadmap that I've ignored for a long while (now's a good time to
> clean up the roadmap too).

The original roadmap's item 8 (2026-10-27) was "Calendar (EventKit), themes, preferences: EventKit read-only overlay
of today's events". Themes and preferences shipped in 0.2.0; the calendar never did. This brief builds it, off by
default, so nothing changes for anyone until they switch it on.

Read `dev/briefs/COMMON.md` (Round 17 block first), `dev/briefs/ROUND-17.md`, `dev/briefs/HIG-NOTES.md`, the design
system README, and how Today and Upcoming build their rows (`TaskListView.swift`, `Views/Upcoming/*`,
`UpcomingSchedule`, core `ListRow`: shared tasks became rows in round 14 the way events must now, without becoming
tasks).

## The rules
- **Read-only, on the device.** HITList shows events from the calendars the person picks. It never creates, edits
  or deletes an event, never syncs one, and events never enter the store, CloudKit, backups, the snapshot, Spotlight,
  Siri's answers or the Claude export.
- **Off by default.** Settings → General gets "Calendar events" (a toggle; iPhone and the Mac's Settings page).
  Switching it on asks for calendar access (full access is what reading needs; the purpose string says read-only in
  plain words). Denied or restricted: the row says so and offers the system's settings, as the Reminders section
  does for notifications. On, a second row picks the calendars (all by default), in a small card in the design
  system's look, each with its colour.
- **Where events show.** Today: the day's events in time order above the day's tasks, under a quiet header of
  their own, all-day events first. Upcoming: each day's events at the top of that day, in the list (iPhone) and in
  the board's columns (Mac, iPad). Nowhere else: not the Inbox, a Group, search, filters, counts or the badge.
- **An event is not a task.** No checkbox, no priority, no swipe, no drag, no editor. A row as tall as a task row
  so the list keeps its rhythm: a 3 pt bar in the calendar's colour where the checkbox would be, the title in the
  secondary text colour, and on the second line the time ("9:30 – 10:15", "All day") in the meta style. A click or
  tap does nothing in this brief (George does not like being handed off to another app; a read-only card can come
  later). Past events of today dim.
- **Fresh.** Reload on `EKEventStoreChanged`, at midnight, when the app becomes active and when the setting or
  the calendar choice changes. Never block the list on EventKit: events arrive after the tasks if they must.

## Items (one commit each, failing test first where there is logic)
1. **The source**: a small service over `EKEventStore` behind a protocol (so tests use a fake), the entitlement
   for the Mac's sandbox (`com.apple.security.personal-information.calendars`), `NSCalendarsFullAccessUsageDescription`
   in `project.yml`'s info for both platforms, and pure functions in core for which events a day shows and in what
   order (all-day first, then by start, multi-day events on each day they cover, time zones and daylight-saving
   days tested).
2. **The setting**: the toggle, the permission states, the calendar picker card; a key in an `extension Preferences`
   of your own (device-local: calendars differ per device).
3. **Today.** 4. **Upcoming**, list and board.
5. **The privacy policy** (`docs/privacy.md` or wherever `docs/` keeps it): one short section, in the page's own
   voice, saying what item "Read-only, on the device" says.
6. **Demo.** A Debug launch argument that feeds a believable day of fake events (`-seedDemoEvents YES`) without
   touching the system calendar, for screenshots and UI tests.

## Ownership
New `HITList/Services/Calendar/*`, new `HITList/Views/Calendar/*`, new core file(s) for the day rules (+ tests),
`HITList/Views/TaskListView.swift` (Today's section only), `HITList/Views/Upcoming/*`, core `UpcomingSchedule` and
`ListRow` only if events need a case there (keep every existing caller compiling unchanged),
`HITList/Views/Settings/GeneralSettingsSection.swift` and the Mac General section if it does not reuse it,
`HITList/HITList-macOS.entitlements` (the one key), `project.yml` (the one usage string; brief 74 edits the same
file, in other places), `docs/` privacy page, new `HITListTests/Calendar*Tests.swift`, a UI test file of your own.
Not yours: `TaskRow` and the design-system styles (75: build the event row as its own small view from `ListMetrics`
and `HITType`, do not edit `TaskRow`); `InboxView`; the popouts; widgets (74: the Upcoming widget shows no events
this round); companions (76); the models and schema (no schema change this round); `dev/ROADMAP.md`,
`CHANGELOG.md`, `WhatsNew.swift`.

## Done
Screenshots with `-seedDemoEvents YES`, iPhone and Mac: Today and Upcoming (list and board) with events, the
setting off (pixel-identical to master), the setting's three states and the calendar picker. What the permission
prompt says on each platform. All three suites green.
