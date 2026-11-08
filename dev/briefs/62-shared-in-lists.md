# Brief 62: shared tasks in your lists (session `shared-in-lists`, effort xhigh)

George, 2026-11-07:

> Shared Tasks have a terrible implementation. They're supposed to show up in my todo list as shared tasks, not in
> some other list; what's the point of that?

Read `dev/briefs/COMMON.md`, then `dev/briefs/ROUND-14.md`, then `51-shared-tasks.md` for how Shared Tasks are built:
their own CloudKit container, `CKSyncEngine`, a JSON store (`SharedTasksStore`), field-stamped merges, all kept out of
SwiftData; `SharedTasksCenter` (observable) holds the lists and tasks; `SharedTasksScreen` and `SharedListScreen` are
the separate screens; `SharedTasksComponents` has the avatar stack and a row drawn like `TaskRow`. Brief 61 has just
cleaned the list views (read `61-lists-cleanup.md` for how the Inbox and Today look now). This brief starts after 61 is
merged, so the list views are yours.

## The rule
A shared task is a task in your lists. Its list is to it what a Group is to a task of yours:
- Dated: in Today (today or overdue), Upcoming (the list, the week strip, the Mac board) and the Inbox, sorted among
  your own tasks by priority then date. Undated: only in its list's own screen, like a note in a Group.
- Sort by Group puts each shared list in a section of its own after the Groups and before "Ungrouped", header
  "👥 Trip · 2" drawn with the two-person glyph (or the list's avatar stack) in place of the dot.
- The row looks like `TaskRow`: title, due, priority colour, and where a Group name would sit, the list's name with the
  people marker. Completing from the row completes it in the shared store (the stamp, the other members see it), with
  the usual toast and Undo. Tapping opens the shared task's editor (the one `SharedListScreen` uses), as a sheet on
  iPhone and the usual panel on the Mac.
- The Shared Tasks screen stays, for the lists themselves: members, invitations, leaving, the preview switch. On the
  Mac sidebar each shared list is a row under "Shared" (after Groups), opening its screen; the Shared Tasks row stays
  for management. On iPhone, Browse's Shared Tasks row stays as 61 placed it, with each list under it.
- Spotlight, Siri and Claude's tools are unchanged (shared tasks stay out of them).

## Items (one commit each, failing test first where there is logic)
1. **A row model both kinds feed.** The lists build rows from `TaskItem` today (`Placed` wraps one). Introduce a row
   value that is either a task of yours or a shared task (`ListRow`), conforming to `FilterableTask` so every rule in
   HITListCore (`TaskOrdering`, `GroupedOrdering`, `FlipboardSwitch.listing`, `UpcomingSchedule`) works unchanged;
   `SharedTask` gets its `FilterableTask` conformance (its list's name as the Group name). Pure tests in core.
2. **A source of shared rows.** `SharedRows` (observable, from `SharedTasksCenter`): the open shared tasks across the
   lists the person is in, as rows, updated when the store changes. Nothing when Shared Tasks is off.
3. **The lists.** Today, Upcoming (list, strip, board), the Inbox and a Group-sorted list take shared rows into their
   rows; `TaskRow` draws a shared row (a `SharedTaskRow` variant in `SharedTasksComponents` may be the body); selection
   and the popout host open the shared editor for a shared row; completion and Undo go through the shared store.
4. **The Mac sidebar's "Shared" rows** and the Mac board's drag (a shared task dragged to another day changes its due
   date in the shared store, or refuses with a word if the member cannot write).
5. **Words and the preview.** The Shared Tasks screen's first paragraph says that shared tasks show in your lists;
   the "Preview" badge stays.

## Ownership
`HITList/Views/Shared/*`, `HITList/Services/Sharing/*`, `HITList/Views/TaskListView.swift`, `HITList/Views/Inbox/InboxView.swift`,
`HITList/Views/Upcoming/*`, `HITList/Views/TaskRow.swift`, `HITList/Views/SidebarView.swift`, `HITList/Views/Popouts/PopoutController.swift`
(opening a shared editor), `HITList/Models/Models.swift` (conformances only), HITListCore `FilterableTask.swift`, new core
`ListRow.swift` (+ tests), `HITListTests/Shared*Tests.swift`, a UI test beside `testTabsAndQuickAdd`.
Not yours: `BrowseView` (61 ordered it; its Shared Tasks row stays), `MobileShell`, `MobileTabBar`, `Views/Flipboard/*`.

## Done
Two simulators, or a simulator and the Debug Mac app, on the Development environment with the shared container: a
shared task due today shows in both members' Today with the people marker; one completes it from the row, the other
sees it gone; Undo brings it back; the Inbox sorted by Group shows the list's section. Screenshots. Three suites green.
