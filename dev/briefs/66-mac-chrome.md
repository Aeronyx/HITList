# Brief 66: the Mac's toolbar and the sidebar's search (session `mac-chrome`, effort high)

George, 2026-11-08, on 0.8.1 (screenshot `/Users/gtrammell/Desktop/HITList/build.noindex/round-15/george-1-mac-toolbar.png`):

> The top right baron Mac is a bit of a mess again; the "Add task" button has duplicate ovals with one being slightly
> smaller, and the Filters tabs have poorly spaced text within their bubbles (first screenshot). And while I do like
> showing how the user could have achieved a Filter themselves using Search, it should also be a bit more obvious
> (which could be done by simply saying putting "Search:" up top before the filter code so the user understands what
> that code is.

> A sleek Search bar should be above the Inbox on Mac on the left bar, and there should be more empty space put between
> this new Search bar and the Profile dropdown, as well as between the Profile dropdown and the top of the app.

> The icons in the top right shouldn't change the width of their pill; as it stands, swapping between the Upcoming and
> Flipboard pages makes the pill jut out slightly to the left as the Volume icon apparently demands more space than the
> three bar Filter icon.

Read `dev/briefs/COMMON.md`, `dev/briefs/ROUND-15.md`, `dev/briefs/HIG-NOTES.md`, and `61-lists-cleanup.md` for how
search works on iPhone (Browse's field: text or a filter query through core `SearchIntent`, "Save as filter"). The Mac
has no search today. The supervisor already moved Filters below Groups.

## Items (one commit each, failing test first where there is logic)
1. **The "+" is one oval.** The Mac toolbar's Add task button (`QuickAddEntry`'s toolbar item, `.glassProminent`) sits
   inside the toolbar's own shared glass, which draws the second, larger oval. One oval, the accent one, in an active
   and an inactive window, same size and place as now (`sharedBackgroundVisibility(.hidden)` on that item is the likely
   fix; check macOS 15 too, where there is no shared glass).
2. **The trailing pill keeps its width.** The view-options control and "…" sit in one glass pill; on the Flipboard the
   first control is the flip-sound speaker, wider than the filter-lines glyph, and the pill grows. Give each control in
   that group the same fixed square frame, whatever its glyph, in `ScreenMenu` (do not edit `FlipboardView`, brief
   69's). A test pins the frame; screenshots of the toolbar on Upcoming and the Flipboard, pixel-identical pill.
3. **A filter's query reads "Search: …".** On a saved filter's screen the toolbar shows "Search:" in the secondary text
   style, then the query in the mono style, with even room inside its capsule (today the text touches the capsule's
   left edge). Make it its own view (e.g. `Views/Search/FilterQueryBadge.swift`) and replace the `Text` in
   `TaskListView`'s toolbar with one call (that one line is yours; brief 64 owns the rest of `TaskListView`). Clicking it
   puts the query in the sidebar's search field (item 4), so the person sees it is a search.
4. **A search field at the top of the sidebar**, above Inbox, sleek and ours (the design system's field look, not a
   default SwiftUI `.searchable` bar): a magnifying glass, "Search" placeholder, ⌘F focuses it, Esc clears it and goes
   back to the screen you were on. Typing shows the results in the detail column as task rows (`TaskRow`), through
   `SearchIntent` exactly as Browse does on iPhone: plain text matches titles and descriptions; a filter query (`#Work`,
   `@waiting & p1`, `overdue`) is applied as a filter, with "Save as filter…" when it is one. Clicking a result opens
   the task's editor as any row does.
5. **Room at the top of the sidebar.** More space between the window's top (the traffic lights) and the profile
   button, and between the profile button and the new search field: try a few values and pick the one that reads as
   one calm column (start from about 8 pt more each); keep the profile's left edge on the Settings gear's line
   (`SidebarView.profileInset`). Before and after screenshots of the sidebar's top.

## Ownership
`HITList/Views/Popouts/QuickAddEntry.swift` (the Mac toolbar item), `HITList/Views/Tabs/ScreenMenu.swift`,
`HITList/Views/SidebarView.swift` (the header above the List's sections: room, `profileHeader`, the new search field;
brief 64 edits the sections), `HITList/Views/Account/ProfileMenu.swift` (only `ProfileButtonMetrics` if the spacing lives
there), `HITList/Views/ContentView.swift` (a `SidebarItem` case for search and its route; 64 adds the Shared Tasks
Group's), new `HITList/Views/Search/*`, the one toolbar line in `TaskListView.swift`, new `HITListTests/MacSearchTests.swift`
(or similar), your `dev/ROADMAP.md` row.
Not yours: `BrowseView` (64), `FlipboardView` (69), `HITTokens` (67), `SyncStatusViews` (68), core `SearchIntent` (use as is).

## Done
Mac screenshots (`scripts/window-shot.sh`): the toolbar on Upcoming and the Flipboard (one "+" oval, the same pill), a
saved filter's toolbar with "Search:", the sidebar's top before and after, the search field with "milk" and with
`#Work` typed and their results. All three suites green.
