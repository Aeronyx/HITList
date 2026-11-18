# 161: Upcoming's Week layout: the week's tasks on a calendar (code)

George, 2026-11-18: "The Upcoming page should have a Task-based layout (the current layout) and also a new Week view
that shows tasks on the calendar for that week (first screenshot is an example/reference)." His reference (described;
build HITList's own, in its design system, not a copy): a title bar with a layout button; "Nov 2026 ›" at the left
and a red "Overdue" at the right; three day columns on an iPhone ("Wed 18" with today's number in a filled circle,
"Thu 19", "Fri 20"); under the headers a band of all-day chips (two shown, then "4 more", with a control that opens
and closes the band); below it a grid of hours down the left side that scrolls, a task with a time drawn at its hour
in its day's column, and a line across at the present time with the time at its left.

**Yours**: `HITList/Views/Upcoming/` (new files `UpcomingWeek….swift` are welcome; keep `UpcomingView.swift`'s list
and `UpcomingBoard.swift`'s board exactly as they are apart from the switch), a hosted test file
`HITListTests/UpcomingWeekTests.swift`, a UI test file `HITListUITests/UpcomingWeekUITests.swift`. **Not yours**:
`TaskRow.swift`, `TaskListView.swift`, `Views/Popouts/` (agent 162), `Views/Settings/` (163), `Views/Tips/` (162),
`TaskActions.swift`, the models, anything under `SyncEngine/`. Call what exists there; change nothing in it.

1. **Two layouts, one switch.** Upcoming keeps today's layout (the list on iPhone; the board on the Mac and a wide
   iPad) and gains "Week". The switch sits in Upcoming's own bar where the reference has it (one button with a menu of
   the two layouts, the current one ticked), on every platform. The choice is kept per device in `AppGroup.defaults`
   under one new key; **the default is today's layout**, so nobody's Upcoming changes until they choose.
2. **What a day shows is what Upcoming's list shows for that day**: the same tasks on the same days, from the same
   source (`UpcomingSchedule`, shared rows included if the list shows them), completed ones as the list treats them.
   Put the arrangement in a pure value type (days → all-day items and timed items with a column and a span for the
   ones that overlap) and test it: a hosted test that, for the demo week (`-seedDemoData`'s data) and for a store
   with repeats, sub-tasks and completed tasks, the Week layout's items per day equal the list's.
3. **The Week screen.** Month and year with the week's place in it; previous week, next week, and a way back to
   today. iPhone: three days across, moved sideways a day at a time by a swipe that settles on a day; iPad and Mac:
   the seven days of the week (the week's first day is the app's existing preference, as `WeekStripView` reads it).
   Day headers as the reference. **The all-day band**: tasks with a date and no time; two rows, then "N more" that
   opens the band, and closes again. **The hours**: one scrolling grid, opened at the present hour (or 8 AM when
   today is not shown); a timed task is a chip at its time, at least 28 pt tall, its title on one line; tasks at
   the same time share the column's width. **The present time**: a line across today's column with the time at the
   left, redrawn by a `TimelineView` of its own each minute and only while the screen shows (nothing else in the app
   may tick: at rest the app does nothing, the rule since round 26).
4. **A chip** carries the task's priority colour (the app's own, `Formatting.swift`) and its title. A tap opens the
   task exactly as a row's tap does in the list. If the list's own completion action (with its Undo) can be called
   from the chip's ring without copying it, the ring completes; otherwise the ring is not a control. VoiceOver reads
   a chip as the list reads the row (`TaskRowSpeech`). Dynamic Type: the chips and hour labels scale; nothing clips
   at the largest ordinary size.
5. **Overdue**: when anything is overdue, a red "Overdue" in the header opens the overdue tasks in the list's own
   rows (a sheet or popover; the smallest thing that is right). Nothing when nothing is overdue.
6. Optional, only if items 1 to 5 are whole and proven: a tap on an empty hour opens quick add with that day (and
   hour, if quick add's context can carry one). Not in this brief: dragging a chip, calendar events, durations.

Dark themes only, every theme (take the colours from `Theme` and the design tokens, never a literal); no text within
12 pt of a card's or the screen's edge, 8 pt inside a chip sideways, 6 pt between things (George: text near a border
is "lazy and unprofessional"); the iPhone's floating + and its companion stay clear of the grid's last hour
(the lists' bottom margin). Read how Upcoming's list and board are put on screen before drawing anything.

Proof: the hosted tests; the UI test (open Upcoming, choose Week, a demo task's chip is there, a tap opens its
card, choose the list again, relaunch keeps the choice); `HITListTests` whole on the Mac once at the end;
`HITListUITests` and `SweepPolishUITests` on your simulator. **Pictures** (PNG, in your notes folder, named in your
report): iPhone Week with the demo week, band closed and open, a day with two tasks at one time, the largest text
size; the Mac's seven days; one other theme.
