# Brief 136: the calendar, found and whole (session `calendar`, effort xhigh)

George, 2026-11-14:

> Please add calendar/GCal integration

HITList has had calendar events since 0.9.1 (brief 77, `dev/briefs/77-calendar-events.md`): the device's calendars,
read through EventKit, shown in Today and Upcoming, read-only and off by default, behind one switch in Settings →
General. George, who uses the app every day, asked for it as if it were not there. So the feature is not found,
it does not say that Google Calendar comes in through the device's own accounts, an event is a row that does
nothing, and nothing goes the other way.

Read `dev/briefs/COMMON.md` (the Round 27 block first), `dev/briefs/ROUND-27.md`, brief 77, the design system
README, `dev/briefs/HIG-NOTES.md`, then `Services/Calendar/*`, `Views/Calendar/*`, core `CalendarDay.swift`,
`GeneralSettingsSection.swift`, `SettingsView.swift` (`SettingsPage`), `Views/Settings/Mac/MacSettingsSection.swift`.

## The rules
- **Still on the device.** Events never enter the store, CloudKit, backups, the snapshot, widgets, Spotlight,
  Siri's answers or the Claude export. HITList signs in to nothing: no Google sign-in, no Google API, no network
  call of its own. Google Calendar, Outlook and iCloud arrive through the accounts the device already has.
- **No schema change, nothing synced, nothing polled.** Reload on `EKEventStoreChanged`, at midnight, on becoming
  active and when a setting changes, as now. Round 26's rules hold: no timer with nothing pending.
- **HITList writes to a calendar only when the person says so, one event at a time** (item 4), and never changes
  or removes an event afterwards except by that toast's Undo.

## Items, in this order (one commit each, failing test first where there is logic)
1. **A page of its own.** Settings → Calendar on the iPhone and iPad (a row on the first screen, after General:
   title "Calendar", subtitle saying what it does in five or six words) and a Calendar section on the Mac's
   Settings page. The switch, the permission states and the calendar picker move there from General (General's
   subtitle no longer says "calendar"; What's New's old path, if a test pins it, is yours to keep true). The
   calendars are listed **by account** (`EKSource`: iCloud, Google, Exchange, Subscribed, Birthdays…), each with
   its colour, all on by default, in the design system's rows (no default `List`, `Toggle` or `Picker` look).
2. **Google Calendar's way in, in words.** A short group on that page, shown while the device has no Google
   account among its calendar sources: what to do, as a real path for the platform it is read on. Check both
   paths on the real things before you write them (the iPhone simulator's Settings app; this Mac's System
   Settings): on iOS it has been Settings → Apps → Calendar → Calendar Accounts → Add Account → Google; on the Mac
   System Settings → Internet Accounts → Add Account → Google, with Calendars switched on. When a Google source is
   there, the group says in one line that Google Calendar is connected through this device's accounts. No button
   that leaves the app (George does not like being handed to another app); words only.
3. **An event's card.** A tap or click on an event row opens a small read-only card in the design system's card
   look (as the pickers': inside the window, never a sheet, closes on a tap outside and on Escape): title, day and
   time range ("All day", and its own time zone when that differs from the device's), the calendar's name and
   colour, the place, the first lines of its notes, its link as text that can be copied. No edit, no hand-off.
   VoiceOver reads it as one element with the same facts.
4. **Add to Calendar.** A task that has a date gets "Add to Calendar" in the row's context menu (long-press on
   iPhone) and in the editor's menu: one event in the calendar chosen on the Calendar page ("Add tasks to": the
   device's default calendar until one is picked, and only calendars that allow changes are offered), titled as
   the task, at its time for 30 minutes, or all day when it has none, the task's notes as its notes, its link
   `hitlist://task/<id>` as the event's URL, no alarm (HITList reminds). A toast says "Added to <calendar>" with
   Undo, which removes that one event. A task already on the calendar (an event with that URL on that day) says
   "Already on your calendar" instead of adding a second. It asks for write-only access when events are not
   shown (`requestWriteOnlyAccessToEvents`; add `NSCalendarsWriteOnlyAccessUsageDescription` in plain words), and
   uses the full access it has when they are. The event is a copy: the page says once, in a footer, that changing
   the task later does not change it. Repeating tasks: one event for the next occurrence, not a repeating event.
5. **Being found.** One tip in the app's tip style (`HITTips.swift`; tips never push the layout and close on a tap
   anywhere on them), shown once in Today while events are off: that the day's calendar can show here, and where
   the switch is (Settings → Calendar). No prompt for permission until the person flips the switch.
6. **The privacy page** (`docs/`): the section brief 77 wrote, brought up to date in the page's own voice (reads
   to show; writes one event only when you choose Add to Calendar; nothing leaves the device).
7. **Demo and tests.** `-seedDemoEvents YES` keeps working and gains two accounts with calendars (one named
   like a Google account) and a writable fake, so the page, the card and Add to Calendar can be photographed and
   UI-tested without the system's calendar or its permission dialog. The source protocol grows what item 4 needs;
   the fake records what would have been written. Extend `CalendarEventsUITests`.

## Ownership
`HITList/Services/Calendar/*`, `HITList/Views/Calendar/*`, core `CalendarDay.swift` and its tests,
`GeneralSettingsSection.swift` (the rows leave), `SettingsView.swift` (the `SettingsPage` case, its row, its
content: nothing else in that file; 135 may add one footer line at the bottom of the first screen),
`Views/Settings/Mac/MacSettingsSection.swift`, `MacSettingsPage.swift` and `SettingsRouter.swift` as far as a new
section needs, the event row's tap in `TaskListView.swift` and `Views/Upcoming/*`, the one menu item in
`TaskRow.swift`'s context menu and in the editor's menu (`Views/Popouts/TaskPopout.swift` or its menu file),
`HITTips.swift` (one tip), `project.yml` (the one usage string), `docs/` privacy page, `HITListTests/Calendar*Tests`,
`HITListUITests/CalendarEventsUITests.swift`, and the lines of `SettingsTests` that list pages. Not yours: the
models and schema, `TaskActions`, the companion files (132–135), `DataSettingsGroups.swift` and import (137), the
sync files, `ICloudSettingsGroups.swift` and the bolt's views (the supervisor), `AboutSettingsGroup.swift` and
`ThemeCompanion.swift` (135), widgets, `scripts/`, `dev/`, `CHANGELOG.md`, `WhatsNew.swift`, the What's New pin.

## Done (report due 22:00 Eastern)
Design and core work first; boot your one simulator (`HITList-136`) only after 20:45 (siblings are booting
theirs). Pictures with `-seedDemoEvents YES`, iPhone and Mac: the Calendar page (off, on, denied), the Google
group in both states, an event's card in Today and in Upcoming, Add to Calendar's toast and "Already on your
calendar". What each permission prompt says. All three suites green and your UI class. The report COMMON asks
for, with what George must do on his devices (the switch; adding his Google account if it is not there) as click
paths, and the choices he might reverse (30 minutes, a copy that is not kept in step, the tip).
