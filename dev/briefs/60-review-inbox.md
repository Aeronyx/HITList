# Brief 60: Review Inbox, simpler and swipeable (session `review-inbox`, effort high)

George, 2026-11-07:

> Finally, while we can keep the Review Inbox feature, change it so that it only goes through undated/ungrouped
> tasks (such as tasks you added without any quickadd highlights and while you weren't in the Today pane, thus going
> to the bottom of the Inbox by nature as they have no priority, date, or group) so the app can function like a
> "brain dump" if needed and the Review Inbox feature helps you fix things you may have missed or misplaced.
> However, please make the feature simpler (way less buttons), more obvious about what it does, and perhaps make it
> feel a bit more like Tinder (swipe left/right on a simple interface to sort tasks as needed) or at least have a
> cleaner UX than it does now.

Read `dev/briefs/COMMON.md`, then `Views/Inbox/InboxProcessView.swift` and `InboxProcessQueue.swift`: today the sheet
("Review Inbox…" in the Inbox's menu, `InboxView.swift` line 96) steps through every Inbox task oldest first with a
row of buttons (Today, Tomorrow, Pick date, Group, Label, Delete, Skip) and Mac shortcuts (T M D P L ⌫ → Return Esc).

## Items (one commit each, failing test first where there is logic)
1. **Only the unsorted.** The queue holds tasks with no due date and no Group (not completed, not sub-tasks),
   oldest first: a pure rule in a new core file `InboxReview.swift` (`InboxReview.needsReview(_:)`), used by the
   queue and by the menu item's count. The item becomes "Review 3 unsorted…" (hidden at zero); `InboxText` owns the
   words. The one line in `InboxView.swift` that shows the item is yours; nothing else in that file (brief 57's).
2. **One card, two swipes, three buttons.** The card: the title (editable on tap, as now), "added 3 days ago", the
   notes if any. Swipe right = **Today** (the card flies off to the right; a green edge glow while dragging and a
   "Today" stamp fading in past the threshold); swipe left = **Delete** (red, a "Delete" stamp; the undo toast as
   everywhere). Under the card three big buttons: **Pick a date**, **Move to a Group**, **Later** (keeps it in the
   Inbox and moves on; drop the second-skip rule). Labels, Tomorrow and the rest live in the task editor, reached by
   a small "Edit…" text button. The swipe is a pure state machine (`InboxReviewSwipe`: offset and velocity → none /
   armed / committed, threshold about 96 pt), tested; the motion follows `HITMotion` and Reduce Motion (a fade, no
   fly-off).
3. **Obvious.** The sheet's header says "Review Inbox" with "3 tasks with no date or Group" under it and progress
   dots; a first-time tip on the card: "Swipe right for Today, left to delete"; the empty state: "Inbox reviewed"
   with the checkmark. Mac: no swipes; the three buttons plus the existing shortcuts (T today, D date, P Group, ⌫
   delete, → later, Esc close); the Mac card keeps its keyboard hints line.
4. **Fewer pieces.** Remove what the new card does not use (the label popover, Tomorrow); rename the files to
   `InboxReview*` with `git mv` if the diff stays readable, otherwise keep the names and say so.

## Ownership
`HITList/Views/Inbox/InboxProcessView.swift`, `InboxProcessQueue.swift`, `InboxZeroView.swift`, `InboxText.swift`,
`InboxPicker.swift`, the "Review Inbox…" line of `InboxView.swift` only, new `HITListCore/Sources/HITListCore/InboxReview.swift`
(+ tests), the review tip in `HITList/Views/Tips/HITTips.swift` only, `HITListTests/InboxProcess*Tests.swift`, a UI test
beside `testTabsAndQuickAdd`.
Not yours: the rest of `InboxView.swift` and `TaskListView.swift` (57), `TaskRow` (59), the task editor.

## Done
On iPhone: three unsorted tasks reviewed by one swipe right, one swipe left (undone from the toast) and one "Later";
the menu item's count; the empty state; the Mac sheet with the shortcuts. Three suites green.
