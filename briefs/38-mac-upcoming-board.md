# Brief 38: Mac Upcoming as a board of days (branch `mac-upcoming-board`, effort xhigh)

Read `briefs/COMMON.md` first. Sessions 34 (account, data model) and 37 (quick-add highlights) run at the same
time; 35 and 36 start later. The iPhone keeps its Upcoming list exactly as it is.

George's words, from the 0.4.1 (14) feedback on 2026-11-04:

> Can the Upcoming tab of the desktop app look like the fourth attached screenshot instead of a copy of
> the mobile app Upcoming tab? Side scrolling in this tab allows for much easier views of upcoming days
> (only for 7 days ahead).

The screenshot (not available to you) is Todoist's Upcoming board on the Mac: a month label with a picker
("November 2026 ⌄") and "‹ Today ›" above; an Overdue column first with its count and a "Reschedule" link;
then one column per day headed "4 Nov · Today · Wednesday" style, each with its count, cards (checkbox, title,
description's first line, date/time line, project at the bottom right) and an "+ Add task" row at the foot;
columns about 270 pt wide, scrolling sideways.

## Items (one commit each, failing test first where there is logic)

1. **Board model** (`UpcomingSchedule.swift`, test-first in `UpcomingScheduleTests`): columns for a start day
   plus six more (seven day columns: "only for 7 days ahead" is the window, not a limit on how far it can
   move), an Overdue column first when "Show overdue" is on and there are overdue tasks; each column's tasks
   ordered as Upcoming orders them today (priority-then-due within a day, sub-tasks excluded, the week-start
   preference respected for labels); counts; the start day moves by one day with the arrows and back to today
   with Today; the month label follows the first visible day ("November – December 2026" across a month end).
2. **Board view** (new `Views/Upcoming/UpcomingBoard.swift`, plus a card view file if it grows; platform split
   in `UpcomingView.swift`: Mac always, iPad when the horizontal size class is regular, iPhone never). Columns
   ≈ 270 pt, `ScrollView(.horizontal)` with lazy columns, each column scrolls vertically on its own; cards on
   `Theme.surface` with the design system's card radius, the `TaskRow` checkbox (completing works with the
   usual sound, motion and Undo toast), title in `HITType` Mac row size (15), the description's first line,
   the time (and repeat icon), the Group name trailing. Clicking a card opens the task popout as rows do.
   Header: month label (a month menu to jump is optional; arrows and Today are required), ‹ Today ›, and the
   existing view options (Show overdue; "Days shown" has no meaning on the board, so hide it there).
3. **Drag to reschedule** (`TaskRescheduling.swift`): drag a card to another day column to move its date,
   keeping its time of day and its repeat's time (`TaskActions.syncRepeatTime(of:)`, as the round 8 follow-up
   did); dropping on Overdue is not allowed; the drop target column highlights. `Transferable` with the task's
   persistent id, or `draggable`/`dropDestination` with a string id: whichever works on macOS 15 and 26.
   Order within a day stays by priority (no manual ordering).
4. **Overdue Reschedule** (`TaskRescheduling.swift`): the Overdue column's "Reschedule" opens the existing
   reschedule picker for all overdue tasks (today, tomorrow, pick a date), as Today's Overdue section does.
5. **Add task in a column**: the "+ Add task" row opens the Mac quick add with that day as its date (the
   way the iPhone's Upcoming add or a Group's add pre-fills context; read `QuickAddContext.swift` and add a day
   context there if none exists; that file is otherwise nobody's this round).
6. **Render check**: the session cannot see the Mac screen. Render the board offscreen in a test
   (`ImageRenderer` or an `NSHostingView` snapshot of `UpcomingBoard` with sample tasks across Overdue and
   three days) to a PNG under `build.noindex/` and look at it with Read; iterate on spacing until it reads
   like the description above. Run the iPad simulator (iPad Air or Pro 13", your own simulator per COMMON)
   in landscape for a real screen of the board.

## Ownership

`HITList/Views/Upcoming/UpcomingView.swift` (platform split; session 35 may change one `screenChrome` call site
line in it for the iPhone, so keep the iPhone branch as is), new `Views/Upcoming/UpcomingBoard.swift` (+ card
file), `UpcomingSchedule.swift`, `TaskRescheduling.swift`, `QuickAddContext.swift` (a day context only); tests
`UpcomingScheduleTests` and a new `UpcomingBoardTests`; `project.yml` only to add files, then `xcodegen
generate`; ROADMAP row "Mac Upcoming board (brief 38)".

Not yours: `TaskRow.swift` (reuse its checkbox view; if it is not reusable, report it rather than refactor),
`TaskActions.swift` (call it), `Views/Tabs/*` (35), Popouts (36, 37), model and Settings files (34).

## Done

All three suites green; the offscreen PNG(s) of the board and iPad simulator screenshots in landscape; tests for
the column model, the window moving, drag-to-reschedule keeping the time and the repeat time, and the add
context. The report lists what George should look at on the Mac (drag feel, scrolling, the header) since no
session can.
