# Brief 131: where the creatures sit on the theme boxes in Settings (0.9.9)

Read `dev/briefs/COMMON.md` (the Round 25 block first), then this. **Sheet due 30 minutes after you start; report
90 minutes after you start.** Effort: xhigh.

## George's words (2026-11-12, on 0.9.8)
"For the Appearance/Theme boxes in Settings:
* Have Quill asleep and almost falling/slumping off the top right corner.
* Position Tuck in the bottom left similar to Button, but perhaps center one of them so they look slightly
  different in terms of positioning.
* Position Glim in the bottom right, having his tail almost hanging over the "Tokyo Night" text.
* Put Gargle somewhere more interesting, like flying in the middle left slightly extended outside of his box or
  maybe just in the bottom left of his box facing right, but definitely not behind his box; only Hush should be
  hiding like that."

## What is there
- `HITList/Views/Settings/ThemeCompanion.swift`: `Placement` (`onCard`, `alongTop`, `peeking`, `asleepOnDot`,
  `onTop`, `onFloor`), `seats` by character id, `layout(for:seat:side:)` (pure, on whole points), `rise`. The
  swatch is drawn in `AppearanceSettingsSection.swift` (`ThemeSwatch`); the theme's name and the creature's name
  stand under each box. Each sprite is drawn still, 1 point a sprite pixel. `SettingsTests` pins the geometry
  (`testEveryCompanionSitsOnItsSwatchOnWholePoints`, `testTheCompanionsSitTheirOwnWayAndANewOneGetsTheDefault`,
  `testButtonStandsOnTheFloorOfHisBox`, `testTheGridKeepsWholePointsAndEvenMargins`).
- Today: Nod on his card; Flint (Gargle, renamed on master) and Hush both peek from behind their boxes; Quill lies
  awake along the top; Tuck and Glim sit on their cards; Phase sleeps on the accent dot; Button stands on the floor
  at the left. The supervisor's picture: `round-25/settings-grid-0.9.8.png` in the notes folder.
- Frames that already do most of this: Quill's `drape` (asleep, his hindquarters and tail hanging down past his
  right side: it is how he sleeps on the shoulder of the "+"); Glim's `rest` (his tail runs out to the right and
  the lantern hangs three rows below his seat row, 15).

## What to make
1. **Quill asleep, slumping off the top right corner** of Midnight's box: lying on the top edge at its right end,
   asleep, with enough of him past the corner and down the side that he looks about to slide off. Start from
   `drape`; if at 1 point a pixel it does not read as "about to fall", add one frame for the swatch only at the end
   of `Quill.swift` (asleep, a paw and the tail hanging, the head on the edge), changing no frame he has.
2. **Tuck at the bottom left, Button at the bottom centre** (or the other way round if that looks better: say
   which and why): both on the floor of their boxes as Button is now, one against the left, clear of the rounded
   corner, the other centred, so the two do not look like one idea twice.
3. **Glim at the bottom right**, on the floor at the right, clear of the corner, his tail over the edge and the
   lantern hanging below the box toward "Tokyo Night": close to the text and never on it (at least 2 points clear
   of the tallest letter at every text size the grid supports). Start from `rest`; a swatch-only frame at the end
   of `Glim.swift` only if the tail must hang straighter. The lantern keeps its glow if the swatch can show it.
4. **Flint in the air at the middle left of Graphite's box, a little outside it**: a new placement, the sprite's
   centre near the box's left edge and its middle height, three to six points of him past the edge, turned to face
   into the box. Brief 128 is drawing him now and will commit a frame named `fly`; until it lands use `fly` if the
   character has it and `rest` if not, and build the placement and its tests on the geometry alone. The supervisor
   will tell you when `fly` is on master: tune the seat on the real drawing then (a second, short pass).
5. **Nod, Hush and Phase stay.** Hush is then the only one behind a box.
6. **What must hold.** Whole points. Nothing cut off by the cell, the card's clip or a neighbour; nothing over a
   theme's name, the selection ring or the accent dot's centre; the grid's row height and the first screen's
   content on an iPhone 16 unchanged (what hangs out the left, right or bottom must fit in the gaps there are:
   measure them, on iPhone 16, iPad and the Mac's Settings); VoiceOver and the tap that picks the theme as before.
   Neighbours across the grid still sit differently, and the test of that says what "differently" now means.

## The sheet (30 minutes)
The grid as it is and as you make it, on an iPhone 16 simulator and on the Mac, at real size and enlarged three
times; one alternative for Quill and one for Glim. Send the supervisor its path and your picks with one line each,
and carry on.

## Ownership
`Views/Settings/ThemeCompanion.swift`; in `AppearanceSettingsSection.swift` only what lets a sprite hang outside
its box; the `ThemeCompanion` tests in `SettingsTests.swift`; swatch-only frames appended to `Quill.swift` and
`Glim.swift` (no existing frame, mode or routine of theirs changes) and the line of the shared test that lists
which frames are in use. Not `Flint.swift`, `Tuck.swift`, `Button.swift`, `Nod.swift`, `Phase.swift`: siblings own
them.

## Done
- The grid before and after on iPhone 16, iPad and Mac in `131-swatch-seats/` in the notes folder, at 1x and 3x.
- `scripts/test.sh macos` and `ios` green (your own simulator, `HITList-131`), and `SettingsTidyUITests` if it
  looks at the grid.
- The report COMMON asks for, with every choice George may reverse.
