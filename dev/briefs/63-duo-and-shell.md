# Brief 63: the iPhone Duo's type and island, and tab switches (session `duo-and-shell`, effort high)

George, 2026-11-07, from the friend testing on the iPhone Duo (screenshot: Today on the outer display, the island
upright at the right with the "+" under it):

> * Can the font be slightly larger?
> * The home buttons on the right don't have much space to breathe.

and:

> Clicking on Browse on a page and then tabbing away and then back to that page should not still show it on the
> Browse subpage.

Read `dev/briefs/COMMON.md`, then `dev/briefs/ROUND-14.md`, then `45-iphone-duo.md` and `50-duo-hinge.md` for the Duo
layouts: the outer display is the compact shell with the island upright in the system's bar column
(`IslandPlacement.side`, `IslandMetrics.side*`), the inner display is the sidebar layout (`AppShell.duo`).

## Items (one commit each)
1. **Slightly larger type on the Duo's outer display.** Where the island stands at the side, a task row's title and
   its meta line go up one step (the title 16 → 17 pt keeping its −0.3 tracking, the meta 12 → 13; large titles and
   section headers unchanged), through `HITType` variants chosen by `\.islandPlacement`, not by device model. Pin the
   sizes in a test. Nothing changes on other iPhones.
2. **Room around the island.** Upright, each tab cell gets 60 pt (was 52), the island 66 pt wide (was 60), the pill
   inset with it, the gap between icon and label 5 pt, and the "+" 16 pt under the island (was `addButtonGap`). Keep
   the island inside the bar column and centred on the camera as `IslandPlacement.sideOffset` does; update
   `sideMinimumWindowHeight` for the new height so the fallback to the bottom island still triggers where the column
   is too short. `MobileChromeTests` pins the metrics.
3. **Tab switches reset the other tab.** Leaving a tab pops its stack to its first screen (Browse and anything pushed
   from it are gone when you come back); re-tapping the current tab keeps popping it as now. `place` reporting follows.
   A UI test: open Browse, switch to Today, switch back, the Inbox is at its root.
4. **Check it on the Duo simulator** (both displays, folding through Device Hub's AX buttons as brief 50 did) and on
   the iPhone 17 simulator, with screenshots of Today on the outer display before and after.

## Ownership
`HITList/Views/Tabs/MobileShell.swift`, `HITList/Views/Tabs/MobileTabBar.swift`, `HITList/Views/TaskRow.swift`,
`HITList/Support/DesignSystem/HITTokens.swift`, `HITList/Views/Duo/*`, `HITListTests/MobileChromeTests.swift`,
`HITListUITests/HITListUITests.swift` (your test only; 61 edits other tests in it).
Not yours: `TaskListView`, `InboxView`, `BrowseView`, `ScreenMenu`, `ListChrome` (61); `Views/Shared/*` (62).

## Done
Screenshots of the outer display's Today before and after, with the island; the metrics test; the UI test for the
tab reset. Three suites and the UI tests green.
