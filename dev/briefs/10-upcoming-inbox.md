# Brief: Upcoming view and Inbox polish, Todoist-style

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first.

## Files you own
New files under `HITList/Views/Upcoming/` and `HITList/Views/Inbox/`, new test files in
`HITListTests/`. In `HITList/Views/ContentView.swift` you may change only the detail routing so
`.upcoming` shows your `UpcomingView` and `.inbox` shows your `InboxView` (which may wrap the existing
`TaskListView`); keep `SidebarItem` as it is. Do not edit `SidebarView.swift`, `TaskListView.swift`,
`TaskRow.swift`, `QuickAddBar.swift`, or `SettingsView.swift`. Reuse `TaskRow`, `QuickAddBar`,
`TaskActions`, `DueFormatter` as they are.

## Goal
Todoist's Upcoming is the best calendar-ish task view around; HITList's is a flat list. Build the
real thing, and make Inbox the calm default landing place it should be.

## Task, three commits
1. **UpcomingView.** A horizontally scrollable week strip at the top (7 day cells, today highlighted
   with `Theme.accent`, dot under days that have tasks, tap to jump, swipe/arrows to change week, a
   "Today" button). Below it a vertically scrolling list of day sections starting today for the next
   30 days, each header "Tue · Oct 28 · Today" style with the count, lazily extending as you scroll.
   Overdue tasks live in a first collapsible "Overdue" section with a "Reschedule all to today" button.
   Each day has an inline "+ Add task" row that opens the quick-add prefilled with that date (post
   the existing `.focusQuickAdd` mechanism if it can take a date; otherwise create the task with that
   due date via `TaskActions.create` after a small inline text field). Dates with no tasks show a quiet
   "Nothing due" line. Section headers pin while scrolling. Both platforms, slate theme, Reduce Motion
   respected.
2. **Drag to reschedule.** Drag a task row onto a day cell in the week strip or onto another day
   section header to reschedule it (`TaskActions.reschedule`, keep time). Use the SwiftUI drag/drop
   APIs with the task UUID as the transferable; show a drop highlight. Keyboard on macOS: with a row
   selected, ⌘→ / ⌘← move it a day. Context menu on a row: Today, Tomorrow, Next week, Pick date…
   (DatePicker popover).
3. **Inbox polish.** `InboxView` wraps the existing list for `.inbox` and adds: an empty state
   ("Inbox zero. Nice.") with a subtle illustration made from SF Symbols in slate colours, a header
   count, and a "Process" mode: a button that steps through inbox tasks one at a time in a card with
   big buttons Today / Tomorrow / Pick date / Move to project (menu of projects) / Delete, so the inbox
   can be cleared quickly. Keyboard shortcuts for those on macOS (T, M, D, P, ⌫). Tests for the pure
   parts: day-section grouping (including tasks with and without time, overdue, far future), week
   strip date math across month/year boundaries, and the Process queue ordering.

## Verify
Signed simulator and Mac builds; create tasks across several days, drag one to another day, use
Process mode on the inbox. Record a short simulator video (`xcrun simctl io booted recordVideo`) and
mention its path. Add a "Upcoming + Inbox" row under a "UI" heading in ROADMAP.md's status table marked
done. Report per COMMON.md.
