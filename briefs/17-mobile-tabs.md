# Brief 17: iPhone tab bar and the four screens (Inbox, Today, Upcoming, Browse)

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first (especially "Where things stand" and
"Round 3 ownership"), then `HITList/Support/DesignSystem/README.md`. Build only on the design system.

## Why (George, 2026-10-31, after using build 4 on the iPhone)
"There should be four buttons across the bottom at all times, representing the four main screens of the
app: Inbox, Today, Upcoming, Browse. There should also be a large, thumb-sized, ovular '+' button to add
tasks that always exists in the bottom right of every screen, above and to the right of the Browse button."
Today is by far the most used screen. The Mac keeps its sidebar; this brief is the iPhone shell plus the
list rules below, which apply on both platforms.

## Files you own
`HITList/Views/ContentView.swift`; new `HITList/Views/Tabs/` (tab bar, Browse page, search); 
`HITList/Views/TaskListView.swift`; `HITList/Views/TaskRow.swift`; `HITList/Views/SidebarView.swift`;
`HITList/Views/Inbox/*` (list rule only; keep Process mode working); `HITList/Views/Upcoming/*`;
`HITList/Views/Popouts/QuickAddEntry.swift` (the iOS floating "+" and where it lives; nothing else in
`Popouts/`, another session is rewriting the card); `HITList/Support/Formatting.swift` (section titles);
a new pure file `HITListCore/Sources/HITListCore/TaskOrdering.swift` + its tests (do not edit
`FilterQuery.swift` or `QuickAddParser.swift`); `HITListTests/` new tests; ROADMAP row named below.
Do not touch `HITTokens.swift`, `Models.swift`, `SchemaVersions.swift`, `TaskPopout.swift`,
`QuickAddPopout.swift`, anything under `Flipboard/`.

## Know before you start
- Popouts: `PopoutController` (environment) presents the quick-add card and the task popout;
  `.quickAddEntry(context)` on a list records the list's `QuickAddContext` (what a new task defaults to)
  and today draws the floating "+" on iOS. Keep calling `.quickAddEntry(context, showsButton: false)` from
  the lists and draw the one "+" in the tab chrome instead, calling `popouts.openQuickAdd()` (it uses
  `popouts.listContext`). Opening a task is `popouts.open(task)` or `List(selection: popouts.selection)`.
- Colours: `HITColor.due(date, hasTime:now:)` gives George's rule (today green, tomorrow orange, later
  purple, overdue red) and `TaskRow` already uses it. Use it for section headers too ("Overdue" red,
  today's header green). Fonts: `HITType` roles only (Inter); never `.font(.subheadline)`.
- `FilterQuery.defaultSort` is due-then-priority; George wants priority-then-due in Inbox and Today. Put
  the comparator and the Inbox membership rule in `TaskOrdering.swift` (pure, tested) and use them from
  the views; leave `FilterQuery` as is (saved filters keep their order).
- `DueFormatter.sectionTitle(for:now:)` (Formatting.swift) names day sections today; extend it for
  "Oct 31, Saturday".
- iPhone only means `horizontalSizeClass == .compact`; iPad and Mac keep `NavigationSplitView`.
- Schema V2 added `deadline`, `locationName`, `reminderOffsetMinutes` (quick-add session) and
  `flipTarget`/`flipCount`/`flipPeriodStart` (Flipboard session). You don't need them; don't display them.

## Task, in commits
1. **Tab shell (iPhone).** On compact width `ContentView` shows a custom bottom bar, not the system
   `TabView` look: four items Inbox (`tray`), Today (`calendar` with the day number, Todoist-style),
   Upcoming (`calendar.badge.clock`), Browse (`square.grid.2x2`), Inter labels under the icons, slate
   `Theme.surface` bar with a hairline top separator, accent for the selected item. Each tab holds its own
   `NavigationStack`. The "+" is a thumb-sized oval (about 64×48 pt, accent fill, `HITColor.onAccent`
   plus sign, soft shadow) sitting above and to the right of the Browse item, present on every tab and in
   every pushed screen (a Group, a label, a filter), hidden only while a popout is up. The bar and the "+"
   are part of `PopoutHost`'s content so popouts draw over them.
2. **Today.** Two sections: "Overdue" (red header) and the day header "Oct 31, Saturday" (green header,
   `DueFormatter.sectionTitle`). Sort each section by priority (P1 first) then due date/time, then title.
   Rows under the day header hide the date (they are all today); keep the time if the task has one.
   Overdue rows keep their red date. Same on Mac.
3. **Inbox rule.** Inbox shows every dated task (in any Group) plus undated tasks with no Group, as one
   list sorted by priority then due date (undated last). Undated tasks inside a Group appear only when
   browsing that Group (they act as notes). Apply the rule to Inbox's list, its count, Inbox-zero and the
   Process queue. The Today and Upcoming screens never show undated tasks.
4. **Upcoming.** Keep the week strip and day sections; sort within a day by priority then time. Make sure
   tapping a strip day jumps to it on iPhone; the strip stays near the top.
5. **Browse.** A page like the Mac sidebar: a search field at the top (`HITField`, searches titles and
   notes of all tasks including completed ones; results in a list that opens the task popout, completed
   rows struck through), then sections: Groups (Inbox first as the default grey Group, then the projects
   with their colours and open counts), Labels, Filters, then rows for Completed, Flipboard and Settings.
   Section headers carry the "+" the Mac sidebar has. Pushing a Group/label/filter shows `TaskListView`
   for it with the "+" still visible and `.quickAddEntry` set to that Group.
6. **"Group" wording.** User-facing text says Group/Groups where it said Project/Projects (sidebar header,
   Browse, editors' titles, "Move to…", chip labels you own). Model and filter syntax stay `Project` /
   `#name` / `project:`; the filter help may say "group (project)". Inbox is "the default Group".
7. **Tests and docs.** `TaskOrdering` tests: comparator (priority then due then title, undated last),
   Inbox membership (dated in a Group → in; undated in a Group → out; undated no Group → in), Today
   sectioning (overdue vs today, nothing undated or future), Browse search matches completed tasks.
   ROADMAP: row "iPhone tabs + four screens (Inbox/Today/Upcoming/Browse, oval '+')" under UI, marked done.

## Verify
Signed iPhone 17 simulator build. Record a video: switch all four tabs, open a Group from Browse (the "+"
stays), search a completed task, show Today's two sections with hidden dates, show an undated task in a
Group that is absent from Inbox. Mac build and tests green (`scripts/test.sh`). Report per COMMON.md.
