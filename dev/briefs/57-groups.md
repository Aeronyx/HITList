# Brief 57: Groups that make sense (session `groups`, effort xhigh)

George, 2026-11-07, after a friend's first week with the app:

> We also need a much better/clearer Grouping system that is different from Tagging so the user understands when to
> use which, and the Grouping system needs an upgrade in terms of UI/UX. My friend usually views his tasks in Groups,
> and he wants to be able to sort both his Inbox and his Today view by Group. It was also pretty awkward to see on the
> mobile app that there was no easy way to view your Groups, The Inbox should also have ways to filter it in general.

Read `dev/briefs/COMMON.md` first, then `HIG-NOTES.md`. In the code a Group is `Project` (the model name never
changed; the UI says Group everywhere). A task is in one Group or none; labels (`TaskLabel`) are tags, many per task.
Inbox = every dated task plus undated tasks with no Group (`TaskOrdering.isInInbox`); undated tasks in a Group are
notes that stay in their Group. Keep both rules.

## Items (one commit each, failing test first where there is logic)

1. **Group by Group, in Inbox and Today.** View options (`ViewOptionsMenu`, the `viewOptions` control in
   `screenChrome`) gain "Group by: None · Group · Priority" for the Inbox and Today lists (Upcoming and the Mac board
   keep their days). Sections carry the Group's colour dot, name and open count, "No Group" last; within a section
   the list keeps `TaskOrdering`. Today keeps its Overdue block on top; grouping applies within it and below. The
   choice is remembered per list in `AppGroup.defaults` (`SettingsPreferences`). The sorting is pure, in a new
   HITListCore file (`GroupedOrdering.swift`; do not edit `TaskOrdering.swift`, brief 59 does), with tests.
2. **Filter the Inbox.** A filter control beside the view options: by Group (several), by label, by priority, and
   "No date" / "No Group"; the active filter shows as chips under the header, each with its ×, and "Clear". Build it
   on the filter language (`FilterQuery`): the control writes a query, the list evaluates it, so "Save as filter…"
   comes almost free (do it if it is cheap). The query building is pure and tested.
3. **Groups one tap from Inbox and Today on iPhone.** The screen title ("Inbox", "Today") becomes a menu button with
   a chevron: it lists the Groups (dot, name, count), then Labels, then "Browse…"; choosing one pushes that list on
   the current tab's stack, as Browse does (`MobileDestination`, `PhoneStack`). Group-by section headers push the
   same way. The four-tab shell and Browse behind the magnifying glass stay (George's decisions, SUPERVISOR §7).
4. **Say what a Group is and what a label is.** One line under the name field of the Group editor ("A task lives in
   one Group: Work, Home, a project.") and of the label editor ("A label is a tag any task can carry: @waiting,
   @errands."), both in `ProjectEditorView.swift`; the same lines as footers under Groups and Labels in Browse and
   in the Mac sidebar's "+" sheets; the quick-add tip for `#`/`@` says it in a phrase. Plain words, no jargon.
5. **The Group experience, end to end.** Audit on iPhone and Mac and fix what is rough, each as its own commit: drag
   to reorder Groups in the sidebar and in Browse (`sortOrder` exists; filters already reorder); a Group's screen
   header shows its colour and count, and the "+" there defaults the task to that Group (check `QuickAddContext`);
   the editor's Group chip shows the colour dot; the Group editor's colour row and name field match the label
   editor's. List what you changed in the report, with before/after screenshots of two of them.

## Ownership
`HITList/Views/TaskListView.swift`, `HITList/Views/Inbox/InboxView.swift` (all but the "Review Inbox…" menu line, brief
60's), `HITList/Views/ListChrome.swift`, `HITList/Views/Tabs/ScreenMenu.swift`, `HITList/Views/Tabs/BrowseView.swift`,
`HITList/Views/SidebarView.swift`, `HITList/Views/ProjectEditorView.swift`, `HITList/Views/Settings/SettingsPreferences.swift`,
new `HITList/Views/Groups/*`, new `HITListCore/Sources/HITListCore/GroupedOrdering.swift` (+ tests), the `#`/`@` tip text
in `HITList/Views/Tips/HITTips.swift` only, `HITListUITests` (a test beside `testTabsAndQuickAdd`).
Not yours: `TaskOrdering.swift`, `FilterQuery.swift` and the listing rules (59); `MobileTabBar`/`MobileShell` (58);
`Views/Inbox/InboxProcess*`, `InboxZeroView`, `InboxText` (60); `TaskRow` (59); `Views/Flipboard/*` (59).

## Done
Inbox and Today grouped by Group on iPhone and Mac (screenshots); a Group opened from the Today title on iPhone; an
Inbox filtered to one Group and "No date" with the chips visible; the two guidance lines in the editors. Core, macOS
and iOS suites green; the UI test runs.
