# Brief 29: Completing is final until Undo; a deleted task's popout closes; pushes don't wait

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md`, then `toggleCompletion`/`finishCompletion` in
`HITList/Views/TaskListView.swift`, `Inbox/InboxView.swift`, `Upcoming/UpcomingView.swift`,
`HITList/Support/Delight/CompletionAnimator.swift`, `CompletionToastState.swift`, `Views/Delight/CompletionMotion.swift`,
`Views/Popouts/TaskPopout.swift`, `PopoutController.swift`, the task-popout and toast parts of
`PopoutHost.swift`, `Views/Tabs/MobileShell.swift` and `MobileTabBar.swift` (`IslandMetrics`),
`Services/Sync/SyncAppDelegate.swift` and `CloudSyncMonitor.nextImport(within:)`.

## George's decisions (2026-11-02)
1. **No fast-tap toggling.** Tapping a checkbox completes the task; tapping it again while the row is
   still animating out does nothing. Undo is the toast's Undo (or unchecking in the Completed list),
   nothing else. Today a second tap within the animation undoes through the toast's record: remove that
   path for rows in the completion animation; keep unchecking a task that is actually showing as
   completed (the Completed list, "Show completed").
2. **The undo toast must never hide behind the island on iPhone.** George still sees it hidden on his
   iPhone 16. The three lists pad their toast by `IslandMetrics.chromeHeight + HITSpacing.xs` and
   `PopoutHost`'s by the same; find what still hides it (a toast shown by another view? the task popout
   sheet? safe-area differences on iPhone 16 vs 17? the keyboard?) and fix it so every toast on every
   iPhone screen size sits above the "+" and the island. Check the iPhone 16 and iPhone 17 simulators.
3. **A task popout open on a task another device deleted closes by itself** (the Mac panel and the
   iPhone sheet), with no crash and no blank panel: observe the model's deletion (`isDeleted`, the
   context's deletion notification, or the sync import) in `TaskPopout`/`PopoutController`.
4. **The iPhone push handler finishes as soon as the import it waited for has finished.** Today it can keep
   the app awake the full 25 s when the import completed before or during the wait; `nextImport(within:)`
   should resolve on an import that completes after the push was received, immediately if one already
   did. Check the Mac handler for the same.

## Files you own
The completion code in the three list views, `CompletionAnimator.swift`, `CompletionToastState.swift`,
`CompletionMotion.swift`, `TaskPopout.swift`, `PopoutController.swift` (task popout state), the task-popout
and toast parts of `PopoutHost.swift` (session 28 edits the quick-add overlay in the same file: keep to your
region), `MobileShell.swift`/`MobileTabBar.swift` only if the toast fix needs them, `SyncAppDelegate.swift`,
`CloudSyncMonitor.swift`'s `nextImport`, tests (`CompletionAnimatorTests`, `CompletionToastStateTests`,
`PopoutTests`, `SyncLogTests`/`SyncWatchdogTests` as relevant), one ROADMAP row.

## Work
Tests first for every pure piece (animator phases, toast state, nextImport timing with an injectable
clock). Run the iPhone 16 and iPhone 17 simulators for the toast (screenshot each) and the Mac app for the
popout closing on a deletion (delete the task from a second window or a script). `scripts/test.sh core
macos` after each commit, `ios` before the last. Report: what changed per commit, the toast's measured
position on both simulators, test counts, the branch name.
