# 158: the lists at 5,000 tasks: the performance review's findings, fixed and measured again (code)

Round 32's review 154 measured the Debug Mac app at 26 and at 5,000 tasks: a check-off cost 5.2 s of CPU, a list
switch 2 to 3 s, a search keystroke 1.65 s, and a list at rest ran every 60 seconds. Its report, tools and samples
are in the notes folder: `round-32/154-performance-review/` (`REPORT.md`, `launch.sh`, `mx.sh`, `ax`, `hot.py`). **The
same tools measure your result: a finding is fixed when its number is.**

**Yours**: `HITList/Views/SidebarView.swift` and `HITList/Views/Tabs/BrowseView.swift` (not their label-deletion
code: agent 156 is changing that at the same time; keep your hunks apart from it), `TaskListView.swift`,
`HITList/Views/Inbox/InboxView.swift`, `HITList/Views/Upcoming/UpcomingView.swift`, `HITList/Views/Search/`,
`HITList/Services/Widgets/WidgetSnapshotBuilder.swift`, a new file for the sidebar's counts, tests. **Not yours**:
`HITList/Views/Popouts/`, `TaskActions.swift`, `TaskRow.swift` (agent 157), anything under `SyncEngine/`.

In this order, measuring after each:

1. **The sidebar's counts** (finding 1): one `@MainActor @Observable` model that recomputes on this container's
   saves, on an import and on `CalendarChange`, debounced, with one fetch and one loop; the sidebar's own `@Query` of
   every open task and the per-row filters go. On the iPhone's Browse the same model.
2. **The 60-second clocks** (finding 3): removed. If a row really changes at a moment (a timed task turning
   overdue), one `Task.sleep` to the soonest such moment among the listed rows, armed by what is listed; nothing
   runs with nothing pending (the rule since round 26: 0.0% CPU at rest).
3. **The widget snapshot** (finding 5): fetch only what the widgets can show.
4. **Search** (finding 6): the model fed 150 ms after the last keystroke; the field itself never lags.
5. **The lists' bodies** (finding 2), most care here: (c) the grouping without copying a section per row; then (b)
   the rows held and rebuilt when the results, the selection, the options or the day change, so an animation's
   steps do not refilter; then (a) a predicate per list where the list's meaning is exactly a predicate (a Group by
   its id, not completed unless shown). **What a list shows, in what order, with what animation, must not change
   at all**: `ListRow`, `GroupedOrdering` and `TaskOrdering` in core decide it and have tests; add a hosted test per
   list that the rows before and after are the same for the demo week (`-seedDemoData`'s data) and for a store with
   completed tasks, sub-tasks and repeats. If (a) or (b) cannot be made provably the same for a list, leave that
   list's (a) or (b) and say so: a slow list is better than a wrong one.

Proof: 154's table again, the same actions at 26 and 5,000 tasks, before (its numbers) and after (yours), from the
Debug Mac app in `build.noindex/158` on side stores `p158` and `p158b` (`-seedSyncLoad`, `-disableCloudKit YES
-ApplePersistenceIgnoreState YES`; a system dialog may be in front on this Mac: do not touch it, drive your app
with 154's `ax`); a minute at rest on a Group at 5,000 (`ps -o %cpu`): 0.0; the whole of `HITListTests` on the Mac
once at the end; on a simulator of your own (`HITList-158`, an iPhone 16) the list UI tests that exist
(`HITListUITests`, `BrowseUITests`, `SweepPolishUITests`: say which you ran and their result).
