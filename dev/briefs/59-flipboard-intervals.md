# Brief 59: the Flipboard is for intervals, not dates (session `flipboard-intervals`, effort xhigh)

George, 2026-11-07:

> I also think you still don't really understand the point of the Flipboard. It's supposed to be a visual aid for
> repeated tasks that need to be completed within a certain duration but not necessarily on a certain day or at a
> certain time. It also means that, if a task isn't overdue and I'm not looking at the Flipboard, it shouldn't
> appear as a task on my todolist, it should stay visibly separated in the Flipboard. That way, I can set Shaving
> for every two weeks, and if I do it earlier it bumps back two weeks, but if I don't do it/it becomes overdue, then
> it should become a moving daily task/permanent task until it gets checked off again or the switch gets flipped.
> It's meant to be a visual representation of recurring tasks, not a fancy way to give yourself more tasks. What's
> more, my friend noticed that when you delete a Flipboard task/switch, it doesn't delete from everywhere; please fix
> this too. Force Touch should also be able to bring up settings/edit options for Flipboard buttons on mobile.

Read `dev/briefs/COMMON.md`, then `Views/Flipboard/FlipboardRules.swift` top to bottom: a switch is an open recurring
task without a time of day carrying the `flipboard` label (`Flipboard.isMember`); green = due in the future, red =
due today or overdue; a flip restarts the interval from the flip day (`dueAfterFlip`, George's call); chargers
(`flipTarget` > 1) count flips within an interval. All of that stays. What changes is where a switch shows up.

## The rule
- **Green: only on the Flipboard.** A green switch appears in no list: not Inbox, Today, Upcoming (list or Mac
  board), the Duo's next days, a saved filter, search, Spotlight's summaries or Siri's "what's on today", unless the
  query names `@flipboard` itself (then it is listed, so a "switches" filter stays possible). Claude's `list_tasks`
  keeps them (they are tasks) and says they are switches.
- **Red: a task for today, every day.** A red switch is in Today, listed as due today (never under Overdue with a
  past date; the Flipboard keeps "3 days overdue" and the pulsing LED), with a small switch glyph on its row, until
  it is flipped or completed. Completing its row is a flip: the interval restarts from today. It is in the Inbox too
  (the Inbox lists dated tasks), as a today task.
- Ordinary recurring tasks (no label) keep their dates and their lists.

## Items (one commit each, failing test first; the rule lives in HITListCore)
1. **Membership and side in HITListCore.** Move the pure parts of `Flipboard` (`isMember`, `side`, `isOverdue`) into a
   core `FlipboardSwitch`, so any `FilterableTask` can be judged without the app (it needs only `filterLabelNames`,
   `filterIsRecurring`, `filterHasDueTime`, `filterIsCompleted`, `filterDueDate`). The app's `Flipboard` calls it.
2. **Listing.** `TaskOrdering.isInInbox`, the Today query's evaluation (`FilterQuery`), `UpcomingSchedule`,
   `UpcomingBoardModel` and `DuoNextDays` exclude green switches and present red ones as due today, through one core
   function (`FlipboardSwitch.listing(for:now:)` → hidden / today / unchanged) so every list agrees. A query that
   names `@flipboard` opts out of the hiding. Tests for each list kind and for the opt-out.
3. **The Today row.** `TaskRow` shows a switch glyph (`switch.2`) in place of the repeat icon and no date text for a
   red switch; completing it calls `Flipboard.flip` (the toast says "Flipped"; undo flips back).
4. **Long-press on iPhone.** The tile's `contextMenu` (`FlipSwitchTile`, it exists) must open on a long press on
   iPhone with the standard haptic and a preview of the tile, offering: Flip (or Mark done), Flip back to red, Edit
   task…, Flips per interval, Remove from Flipboard, Delete. Check each item works on iPhone, not only on the Mac.
5. **Delete, everywhere.** From the tile's menu and from the task editor, Delete removes the task (and its sub-tasks)
   from the store at once, with the undo toast as elsewhere; the Flipboard's `@Query` drops the tile without a
   relaunch; the Spotlight entry goes (`SpotlightSync`). Reproduce the friend's report first with sync working (two
   simulators, or a simulator and the Debug Mac app on the Development environment with its own suffix) and write
   down what you saw: his Mac was not exporting at all (ROUND-13.md), so the report may have been the sync. If so,
   say so and keep the test you wrote.
6. **Words.** The Flipboard tip (`HITTips.swift`: "Flip a switch when it's done") and the empty state say the rule in
   one sentence each: a switch stays off your lists until it is due. `dev/DESIGN.md`'s Flipboard paragraph gets a line.

## Ownership
`HITList/Views/Flipboard/*`, `HITList/Views/TaskRow.swift`, the Flipboard tip in `HITList/Views/Tips/HITTips.swift`
(57 edits the `#`/`@` tip, 60 the review tip), `HITListCore/Sources/HITListCore/TaskOrdering.swift`, `FilterQuery.swift`,
`FilterableTask.swift`, new `FlipboardSwitch.swift` (+ tests), `HITList/Views/Upcoming/UpcomingSchedule.swift`,
`UpcomingBoard`'s model, `HITList/Views/Duo/DuoNextDays.swift`, `HITList/Services/Spotlight/SpotlightSync.swift`, the
Claude tools' and App Intents' "today" summaries.
Not yours: `TaskListView.swift`, `InboxView.swift`, `BrowseView.swift`, `SidebarView.swift` (57); `MobileTabBar`/`MobileShell`
(58); `Views/Inbox/InboxProcess*` (60). If a list view needs a line to call the core rule, make the core change, put
the line in your report, and the supervisor applies it after 57 merges.

## Done
Two switches on the Flipboard, one green and one red: Today and Inbox show only the red one, as today; Upcoming and
the Mac board show neither; flipping the red one from its Today row turns it green and it leaves Today; a long press
on iPhone opens the menu; Delete removes a switch from the board, Today and Spotlight at once. Three suites green.
