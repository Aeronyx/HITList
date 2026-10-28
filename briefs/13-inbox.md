# Brief: Inbox polish (Process mode), Todoist-style

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first. This is item 3 of `briefs/10-upcoming-inbox.md`,
which the previous session did not reach; items 1 and 2 (UpcomingView, drag to reschedule) are on master.

## Files you own
New files under `HITList/Views/Inbox/`, new test files in `HITListTests/`. In `HITList/Views/ContentView.swift`
you may change only the routing `switch` so `.inbox` shows your `InboxView` (it may wrap the existing
`TaskListView(selection: .inbox, ...)`). Do not edit `SidebarView.swift`, `TaskListView.swift`, `TaskRow.swift`,
`QuickAddBar.swift`, `SettingsView.swift`, `UpcomingView` or the Flipboard files. Reuse `TaskRow`, `QuickAddBar`,
`TaskActions`, `DueFormatter`, the completion animation/toast already used by `UpcomingView` (look at how
`HITList/Views/Upcoming/UpcomingView.swift` hooks `CompletionFeedback`, `recentlyCompleted` and the undo toast,
and do the same).

## Task, two commits
1. **InboxView.** Wraps the inbox list and adds: a header with the count ("Inbox · 7"), an empty state
   ("Inbox zero. Nice.") built from SF Symbols in slate colours (no light backgrounds), and a "Process"
   button in the toolbar.
2. **Process mode.** A sheet/card that steps through inbox tasks one at a time, oldest first: title,
   notes, quick-add-style editing of the title, and big buttons Today / Tomorrow / Pick date… / Move to
   project (menu of projects, with "New project…") / Add label / Delete / Skip. Each action advances to the
   next task; a progress line "3 of 7"; finishing shows the empty state. Keyboard on macOS: T, M (tomorrow),
   D (pick date), P (project), L (label), ⌫ (delete, with undo toast), → (skip), Esc (close). Reduce Motion
   respected; slate theme. Tests for the pure parts: Process queue ordering and advancement (skip puts the
   task at the end once, then it's dropped), the count text, and that moving a task out of the inbox removes
   it from the queue.

## Also
Verify drag-and-drop in `UpcomingView` by hand on the iPhone 17 simulator (`xcrun simctl` + long-press drag
via the UI test driver or `idb` if installed) and on the Mac, and say what you saw; fix small breakage only
if it is inside `HITList/Views/Upcoming/` and under ~20 lines, otherwise report it.

## Verify
Signed simulator and Mac builds, `scripts/test.sh` all green. Record a short simulator video and mention
its path. Update the "Inbox polish" row in ROADMAP.md's UI table to "done <date>". Report per COMMON.md.
