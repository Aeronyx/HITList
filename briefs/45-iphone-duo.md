# Brief 45: ready for the iPhone Duo (branch `iphone-duo`, effort xhigh)

Read `briefs/COMMON.md` first. Six sessions run at the same time; see COMMON's "Round 10 ownership".

George's backburner note, 2026-11-04:

> We need to be optimized/ready for the iPhone Duo, as one of my friends will be using that, and Apple is
> requiring it soon anyways. Make clever use of the dual-sided screen.

What the supervisor found (verify it): Xcode 27.1 has an "iPhone Duo" simulator device type (iOS 27.1 minimum,
`iPhone19,4`) with two integrated displays, 1398 × 2034 px (outer, ≈ 466 × 678 pt at 3×) and 2007 × 2853 px (inner,
≈ 669 × 951 pt), and resizable scenes. No API named "Duo" or "fold" in UIKit's headers; read the SDK's UIKit/SwiftUI
headers and the release notes in Xcode (Help) for what Apple says apps should do (size classes, scene resizing, a
posture or hinge API if one exists) and quote it in the report.

## Items (one commit each, failing test first where there is logic)
1. **Research and a running app**: create your own iPhone Duo simulator (`xcrun simctl create "HITList-45" "iPhone
   Duo"`), install, and screenshot both displays (find how the simulator switches between them: Device menu,
   `simctl` or the display picker). Note the size classes on each.
2. **The right shell per display** (`ContentView.swift`, `MobileShell.swift`): the outer display gets the iPhone
   tab shell; the inner display gets the sidebar layout the iPad uses (sidebar + list, the Upcoming board), if its
   width is regular, or a two-pane layout of your own if it is compact-but-wide. Switching displays (folding/
   unfolding) keeps the user where they were: the current list (tab ↔ sidebar item mapping), an open quick-add card
   with its text (sticky draft), an open editor, scroll position where cheap. Test the mapping logic.
3. **Clever use of the big screen**: on the inner display, the task editor opens beside the list rather than as a
   sheet (a detail column only in this layout; George does not want a detail column on the Mac or iPad), and Today
   shows Upcoming's next days alongside if it fits. Pick one or two that read well; screenshot them.
4. **Everything else adapts**: the "+" oval, the Undo toast and the quick-add card position correctly on both
   displays and through the transition (`PopoutHost.swift`), no clipped sheets, Flipboard's grid reflows.

## Ownership
`Views/ContentView.swift`, `Views/Tabs/MobileShell.swift`, `Views/Popouts/PopoutHost.swift` (placement and size-change
continuity), new `Views/Duo/*`; tests new `DuoLayoutTests`; `project.yml` only to add files; ROADMAP row "iPhone Duo
(brief 45)". Not yours: `MobileTabBar.swift`, `BrowseView.swift`, `SidebarView.swift` (40), `QuickAddPopout.swift`
(39), `TaskPopout.swift` (41; if the side-by-side editor needs a change there, report it), `Views/Upcoming/*` (39).

## Done
All three suites green; iPhone Duo simulator screenshots of both displays (Today, Upcoming, the editor) and of a
transition keeping an open card; the iPhone 17 unchanged (screenshot).
