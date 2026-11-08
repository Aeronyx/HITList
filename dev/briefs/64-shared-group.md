# Brief 64: Shared Tasks as one forced Group (session `shared-group`, effort xhigh)

George, 2026-11-08, on 0.8.1:

> I want Shared Tasks to be their own forced custom Group called Shared Tasks instead of having a dedicated sidebar
> section, and I also want them to look like regular tasks just with profile pics where the labels would normally be.
> Once again, I must emphasize that there's no point in shared tasks if they don't appear to users in the app like
> regular tasks, just with a forced group.

Read `dev/briefs/COMMON.md`, `dev/briefs/ROUND-15.md`, then `51-shared-tasks.md` and `62-shared-in-lists.md`: Shared
Tasks live in their own CloudKit container and JSON store (`SharedTasksStore`, `CKSyncEngine`), never SwiftData;
`SharedTasksCenter` holds the lists, `SharedRows` turns open shared tasks into rows, and `ListRow` (core) lets a task
of yours and a `SharedRow` go through every list rule. Round 14 left three things this brief closes: the Mac's shared
editor panel is drawn by the list column instead of `PopoutHost`; a shared list's own screen keeps the Shared screen's
card look; the badge and the morning summary do not count shared tasks.

## The rule
- **One Group, "Shared Tasks", always there** (it is the way into sharing): last in every list of Groups (the Mac
  sidebar, Browse, the Group card in quick add and the editor, Sort by Group). It has a dot like any Group and cannot be
  renamed, recoloured, reordered or deleted. The separate shared lists stay underneath as they are (members and the
  CKShare live there); the person sees one Group.
- **A shared task looks like a task of yours** (`TaskRow`): the checkbox in its priority colour, the title, the date
  line, and on the right "Shared Tasks" with its dot where a Group sits. Where your task's labels would be, the people
  it is shared with, as small round profile pictures (initials where someone has none), overlapped like an avatar
  stack, in the label slot's height and place. No people glyph and no list name on the row any more. A shared row and
  a task of yours with the same fields are the same height with the title in the same place.
- **The Shared Tasks Group's screen is a Group's screen**: the same large title, one view-options control and sorts as
  any Group's, all open shared tasks, dated or not. With more than one set of people (more than one shared list), a
  section per set, its header the avatars and first names ("Sam & Alex · 3"); with one, no sections.
- **Sharing itself moves into that screen**: "Sharing…" in its view options opens a sheet with what `SharedTasksScreen`
  does today (invite, who is in, leave, the preview switch), restyled with the design system (`HITGroup`, our buttons
  and fields, no default SwiftUI controls). The Mac sidebar's "Shared" section and `SharedTasksSidebarRow`, Browse's
  Shared Tasks section and rows, and `SidebarItem.sharedList(id)` go; the Group's own item takes their place. With
  Shared Tasks switched off, the Group is still listed and its screen says in a sentence what sharing is, with one
  button to switch it on and share.
- **A shared task opens in the editor George knows**: the same layout and components as `TaskPopout` (`EditorCard`,
  `EditorRow`, the pill row, `ConfirmPill`, × and "…"), the Group row reading "Shared Tasks" with its dot, a people row
  with their pictures, and nothing the shared model does not have (no labels, reminder, repeat, deadline, location or
  sub-tasks unless the model already has them). On the Mac it is the panel `PopoutHost` draws, with the dimmed backdrop
  and Discard rules of a task of yours; on iPhone the same sheet. Build it in `Views/Shared` from the editor's
  components as they are; `TaskPopout.swift` is brief 65's except its `groupRow`.
- **Every Group shows its dot, never "#"**: the editor's Group row, the Group card's rows, the quick-add Group chip.
- **Adding**: quick add's `#Shared` (and choosing Shared Tasks in the Group card or chip) makes a shared task; with one
  set of people it goes there, with several to the most recently used, which the editor's people row can change. The
  Mac board's add card and drag work for it as for yours (62 did the drag). Flipboard switches stay personal.
- **Counts**: the sidebar's Today and Inbox counts, the app badge and the morning summary count shared tasks exactly as
  Today shows them. While in that code: a red Flipboard switch counts as one of today's tasks, never as overdue (round
  13's rule: a red switch waits in Today as today's task until flipped).
- Spotlight, Siri and Claude's tools stay as they are (shared tasks stay out of them).

## Items (one commit each, failing test first where there is logic)
1. **The forced Group in the lists' model.** A value every Group list and picker includes last (e.g. a `GroupRef` with
   a `.shared` case, or `ListRow` reporting the Group as Shared Tasks); Sort by Group gives Shared Tasks one section
   after your Groups. Pure tests in core.
2. **Rows.** `TaskRow` draws a shared row like yours: the avatar stack where labels go (reuse
   `SharedTasksComponents`' stack, sized to the label slot), "Shared Tasks" and its dot at the right. A test that a
   shared row and a task of yours measure the same.
3. **The Group's screen and the Sharing… sheet**; the Shared sidebar section, `SharedTasksSidebarRow`, Browse's
   Shared Tasks section and `SidebarItem.sharedList(id)` removed; the Shared Tasks Group last under Groups everywhere.
4. **The editor** for a shared task, through `PopoutHost`/`PopoutController` on both platforms; the list column no
   longer draws a panel of its own (`sharedTaskEditor(owner:)` goes or becomes a thin call).
5. **Dots, not "#"**, in the editor's Group row, the Group card and the quick-add chip.
6. **Adding to Shared Tasks** from quick add (`#Shared`, the chip), the Group card and the Mac board.
7. **Counts**: sidebar, badge, morning summary (shared tasks; red switches as today's).
8. **See it**: two members on the Development shared container (two simulators, or a simulator and the Debug Mac app,
   as 62 did): a shared task due today looks like a task of yours in both members' Today with the other person's
   picture; the Shared Tasks Group's screen; the Sharing… sheet; the editor on the Mac (panel) and iPhone (sheet).
   Screenshots of each, both platforms.

## Ownership
`HITList/Views/Shared/*`, `HITList/Services/Sharing/*`, `HITList/Views/Groups/*`, `HITList/Views/TaskRow.swift` (the
meta line and the Group slot; not `TaskRowMetrics`, which is brief 67's), `HITList/Views/SidebarView.swift` (the List's
sections only; brief 66 owns the header above them: room, profile, search), `HITList/Views/Tabs/BrowseView.swift`,
`HITList/Views/TaskListView.swift` (brief 66 replaces the filter query's toolbar `Text` with its own view, one call),
`HITList/Views/ContentView.swift` (your `SidebarItem` case and its route; 66 adds search's), `HITList/Views/Inbox/InboxView.swift`,
`HITList/Views/Upcoming/*`, `HITList/Views/Popouts/PopoutHost.swift`, `PopoutController.swift`, `PopoutPickers.swift`
(the Group card), `QuickAddPopout.swift` and `CompactQuickAddCard.swift` (only where Groups are known to the parser, the
Group chip, and saving), `TaskPopout.swift` (only `groupRow`), `HITList/Services/TaskActions.swift` (creating a shared
task), `HITList/Services/NotificationScheduler.swift` and `Services/Notifications/*` (badge, morning summary), core
`ListRow.swift`, `FilterableTask.swift`, `GroupedOrdering.swift`, `HITListTests/Shared*Tests.swift`, your UI test in
`HITListUITests/HITListUITests.swift`, your `dev/ROADMAP.md` row.
Not yours: the rest of `TaskPopout`, `Views/Popouts/Editor/*`, `TokenHighlightField`, `Pickers/*` (65; use the editor's
components as they are), `HITTokens` (67), `SyncStatusViews` (68), `Views/Flipboard/*` (69), `ScreenMenu`,
`QuickAddEntry` (66).

## Done
The screenshots of item 8 on both platforms, with a shared task beside a task of yours in Today; the Mac sidebar
without a Shared section; Browse's Groups ending in Shared Tasks. All three suites and the UI tests green. Report the
decisions George might reverse (how several sets of people are told apart, where Sharing… sits).
