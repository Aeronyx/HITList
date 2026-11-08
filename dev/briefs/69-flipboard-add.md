# Brief 69: adding a switch should feel good (session `flipboard-add`, effort xhigh)

George, 2026-11-08, on 0.8.1:

> Flipboard "Add a Switch" UI is awful, especially on mobile. It feels like a dev UI. I want the Flipboard to feel very
> good and satisfying, it'd be more fun if adding the dates/creating the switches was somehow tactile without being
> annoying. Adding switches should have cute popouts that look and feel like the "Add task" card on the Upcoming page
> in the Mac app.

Read `dev/briefs/COMMON.md`, `dev/briefs/ROUND-15.md`, `dev/briefs/HIG-NOTES.md`, `59-flipboard-intervals.md` (the rule:
a switch is a chore that repeats within an interval; green on the board until its interval runs out, then red in
Today and the Inbox as today's task until flipped; `FlipInterval`, flips per interval) and `39-board-inline-add.md` (the
Mac board's Add task card George points at: a small card in place, typing at once, chips, the confirm pill). Today
adding is a full sheet (`FlipSwitchEditor` in `FlipboardView.swift`: "New Switch", a Name field, steppers for "Turns
red" and "Flips per interval", a preview); editing an interval or the flips opens the same sheet from a tile's menu.

## Items (one commit each, failing test first where there is logic)
1. **A small card, in place.** The dashed + tile (and the toolbar's Add Switch…) opens a compact card that looks and
   feels like the Mac board's Add task card: our card shape and glass, the name field focused at once, the interval
   and flips as chips under it, and the confirm pill. On the Mac it opens where the + tile is, inside the grid; on
   iPhone it rises from the bottom like the quick-add card, keyboard up, never a full-height sheet. Tapping away with a
   name typed asks Discard inside the card (George's rule).
2. **Setting the interval is tactile.** Pick "every 3 days", "every week", "every 2 weeks" in a way that feels physical
   without being slow: for example a row of quick choices (Daily, 3 days, Weekly, 2 weeks, Monthly) plus a number you
   can drag or scroll through with a detent haptic per step (`TapHaptic` on iPhone, the trackpad's alignment feedback
   on the Mac), the preview switch showing how it will look (a small rocker, `RockerSwitch`, already green). Typing the
   interval works too: "Water the plants every 3 days" in the name fills the chips the way quick add reads repeats
   (core `RecurrenceRule` / the quick-add grammar), the phrase highlighted. Flips per interval the same way, a small
   tactile count. Tests for what the chips and typed phrases produce.
3. **Editing a switch** (its tile's menu: interval, flips, rename) opens the same card on that tile, filled in, not the
   sheet. The sheet `FlipSwitchEditor` goes once nothing uses it.
4. **It feels good**: the card's entrance and exit use `HITMotion` (`enter`/`exit`), the new tile lands in the grid with
   a small settle, one light haptic on Add (iPhone), the flip sound only when a switch flips (as now). Look at it on the
   iPhone 17 simulator and the Debug Mac app; screenshots of the card empty, typed, with a chosen interval, and the new
   tile; a short frame strip of the entrance.

## Ownership
`HITList/Views/Flipboard/*` (`FlipboardView`, `FlipSwitchTile`, `RockerSwitch`, `FlipSound`, `FlipboardRules` where the
editor's rules live), new files under `HITList/Views/Flipboard/`, `HITListTests/Flipboard*Tests.swift`, your UI test in
`HITListUITests/HITListUITests.swift`, your `dev/ROADMAP.md` row.
Not yours: the quick-add files and `PopoutHost` (read them for the look; use components as they are; if the card needs
the quick-add card's chip or pill views, use them without changing them), `ScreenMenu` (66 fixes the toolbar pill's
width there; your toolbar control may stay as it is), `HITTokens` (67), core `QuickAddParser` (use as is).

## Done
On the iPhone 17 simulator and the Mac: "Water the plants every 3 days" added from the card in a few seconds, the tile
in the grid green; an existing switch's interval changed from its tile. The screenshots and the frame strip. All three
suites and the UI tests green.
