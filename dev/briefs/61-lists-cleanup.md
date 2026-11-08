# Brief 61: the Inbox and Today, cleaned up (session `lists-cleanup`, effort xhigh)

George, 2026-11-07, after releasing 0.8.0 (the Inbox screenshot: a small "Inbox ⌄" title, the bolt, then a pill with a
circled filter icon, a filter-lines icon and the magnifying glass; under it "Inbox · 1" in large type, then a
"Priority 4   1" section header in another type):

> What is the absolute mess going on in the top of the Index page? Two filter buttons? "Inbox" twice, one with a
> random number? Priority 4 1 in different fonts? […] The buttons are also incredibly confusing. The Inbox is, and
> should be, sorted by Priority at default; if the user selects Group, then sort the inbox by Group, and have
> Ungrouped/Unsorted for all the tasks that have no group/Inbox is their only group. Of course, within those Groups,
> still sort by Priority and then Date. The user should also be able to select Date, showing inbox tasks by Date. How
> was that hard to understand? How did we wind up with two buttons and both make no sense? Maybe we're getting groups
> confused with tags/labels, but in any case, this functionality needs to be cleaned up, because it made no sense to
> my friend and it doesn't to me either. "Filters" should also just become part of the search bar as to not further
> confuse users. […] Why is the iPhone title tiny font in the top left, and why is it a button? Since when did I ask
> for that to be a button? I asked for Groups to be the first thing in the top right Browse page. Groups should be
> first above Shared Tasks.

Read `dev/briefs/COMMON.md`, then `dev/briefs/ROUND-14.md` (the rules), then this. Brief 57 (`57-groups.md`) built what
you are reshaping: `Views/Groups/*` (the title menu, `ListFilterControls`, `GroupSections`), `GroupedOrdering` in core,
and the Inbox filter in `InboxView`. Keep what George asked for in 57 and still wants: grouping by Group, the Group
and label guidance lines, drag-to-reorder, the delete-a-Group question. Remove the rest.

## What the screens look like when you are done
**Inbox, iPhone.** Large title "Inbox" (the system large title, as Today and Upcoming have), not a button, no
chevron. The bar: the bolt, then one pill with the view-options icon (filter lines) and the magnifying glass. No
"Inbox · N" header anywhere (the count lives in Browse's Inbox row and the Mac sidebar). Then the list:
- *Sort by Priority* (the default): the flat list exactly as before 0.8.0, priority then date, no section headers.
- *Sort by Group*: a section per Group in sidebar order, header "● Work · 3" (dot in the Group's colour, name, count
  in `Theme.secondaryText`), rows inside priority then date with no Group name repeated; "Ungrouped · 2" last with a
  hollow dot. Headers are not buttons.
- *Sort by Date*: sections "Overdue", "Today", "Tomorrow", the next days by name, "Later", "No date", in the due
  colours (`DueFormatter.sectionTitle`/`sectionColor`, as the filter lists do), rows inside priority then time.
Every header uses `taskSectionHeader` (`HITType.listSectionHeader`), title and count in one `Text` run: one font.

**Today.** Large title "Today", not a button. View options: Sort by Priority (default) or Group; Show completed.
"Overdue" and the day stay on top in both sorts, as 57 built; the day header's font and the Group headers' font are
the same.

**Mac.** The same two menus in the toolbar's view options; the Inbox loses its "Inbox · N" header too. The Mac
sidebar keeps its Filters section (a decision George can reverse).

**Browse (iPhone).** The search field first. Under it the saved filters as a row of chips (tap opens that filter's
list; long-press for Edit… and Delete; a trailing "+" chip makes a new one). Then the sections: Groups (Inbox first,
as now), Shared Tasks, Labels, then Completed and Settings. The "Filters" section is gone. The search field accepts
the filter language: text that reads as a query (`#Work`, `@waiting & p1`, `no date`, `overdue`) filters by it, any
other text searches titles and notes as now. The rule is pure, in HITListCore (`SearchIntent`), with tests; when a
query is typed, a "Save as filter…" row under the field saves it (the filter editor opens to name it).

**A Group's screen.** Large title with the Group's name; drop 57's "● Work · 3" header (the name twice again).

## Items (one commit each, failing test first where there is logic)
1. Remove the Inbox filter: `ListFilterMenu`, `ListFilterChips`, the stored `ListFilter`, the "No matching tasks"
   state, "Save as filter…" from the Inbox, and `Views/Groups/ListFilterControls.swift` (and its core query builder if
   only the Inbox used it; `ListFilterTests` go with it).
2. Remove the title menu (`groupsTitleMenu`, `.navigationBarTitleDisplayMode(.inline)`) and the section-header links
   and chevrons; large titles back on every iPhone list. Remove the "Inbox · N" header and the Group screen's header.
3. "Sort by": the view options' `GroupByPicker` becomes "Sort by" with Priority / Group / Date on the Inbox and
   Priority / Group on Today; the stored keys in `SettingsPreferences` change with it (old values read as Priority).
   Date sort in `GroupedOrdering` (`.date` case) with tests.
4. One header style: `GroupSectionHeader` draws title and count as one run in `taskSectionHeader`; "Ungrouped" (not
   "No Group") with the hollow dot, last.
5. Browse: section order, the filters-as-chips row under the search field, `SearchIntent` in core and the search
   field using it, "Save as filter…".
6. Update `GroupsTests`, the UI tests (drop the title-menu test; keep the grouped ones) and `HITTips` if a tip
   mentions the filter button.

## Ownership
`HITList/Views/TaskListView.swift`, `HITList/Views/Inbox/InboxView.swift`, `HITList/Views/Inbox/InboxText.swift`,
`HITList/Views/Tabs/BrowseView.swift`, `HITList/Views/ListChrome.swift`, `HITList/Views/Tabs/ScreenMenu.swift`,
`HITList/Views/Groups/*`, `HITList/Views/Settings/SettingsPreferences.swift`, `HITList/Views/Tips/HITTips.swift`,
`HITListCore/Sources/HITListCore/GroupedOrdering.swift`, new `SearchIntent.swift` (+ tests), `HITListTests/GroupsTests.swift`,
`ListFilterTests` (delete), `HITListUITests/HITListUITests.swift` (the Groups and Review tests only).
Not yours: `MobileShell`, `MobileTabBar`, `TaskRow`, `HITTokens`, `Views/Duo/*` (63); `Views/Shared/*`,
`Services/Sharing/*` (62, later); `Views/Flipboard/*`, `Views/Inbox/InboxProcess*`.

## Done
Screenshots, iPhone and Mac: the Inbox in each of the three sorts, Today in both, Browse with the chips row and a
typed `#Work` query, a Group's screen. Three suites and the UI tests green. In the report: every screen where a name
still appears twice, if any.
