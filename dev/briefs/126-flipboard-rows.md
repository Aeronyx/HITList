# Brief 126: Switchboards in rows, on a board, with lights (0.9.8)

Read `dev/briefs/COMMON.md` (the Round 24 block first), then this. **Pictures of your design in the running app due
60 minutes after you start; report 180 minutes after you start.** Effort: xhigh.

## George's words (2026-11-12, on 0.9.7)
"Switchboards should grow/scroll horizontally, not vertically, and the "Add switch" button outline should appear at
the right end of each Switchboard scroll. Ungrouped switches can still live at the top and move downwards
vertically in groups of two (on iOS), but they should be collapsible to easily get to your horizontal Switchboards."

"Switchboards should have some kind of mild background UI so that they actually feel like they're a part of the
same circuitboard rather than just switches in a group, and that background UI should also show at all times when
the board is fully green/which switches in the order are red while keeping the UI minimal and clean (small red and
green dots in a row would do it; if there's too many switches to display with dots on that Switchboard, have a
backup UI plan)."

"Adding Switches on iOS makes them expand and contract like crazy for a moment before they settle."

He uses the Flipboard every day, on an iPhone 16 and a Mac. Of spacing he has said (round 22): text right next to a
border "looks lazy and unprofessional"; the floors are 12 pt from text or a control to its card's border, 8 pt from
a label to its chip's border, 6 pt between controls.

## What is there (`HITList/Views/Flipboard/`)
`FlipboardView`: one vertical scroll. First the loose switches in `FlipboardGrid` (two columns on iPhone, 3 to 5 on
the Mac and iPad, 2 or 4 on the Duo's inner display), the dashed `AddSwitchTile` last. Then each Switchboard as a
section: `SwitchboardHeader` (name, a "+", "Daily · resets 04:00 · 3 of 5") and another `FlipboardGrid` that grows
downward. `NewSwitchboardRow` at the foot. The switch card opens in the grid on the Mac and iPad (`inlineCardView`,
`cardSpan`) and floats over the board on iPhone (`FloatingSwitchCard`); a saved switch "lands" (`SwitchLanding`, a
spring from 0.86) while `.animation(.snappy, value: switches.map(\.id))` moves the grid and `proxy.scrollTo` brings
it into view. Dragging a switch onto a board or back (`SwitchDrag`, `switchDropTarget`, brief 96). Rules and order
in `FlipboardRules.swift`, `SwitchboardRules.swift`; tests `FlipboardTests`, `FlipboardAddTests`,
`SwitchboardTests`; UI tests `FlipboardPhoneUITests`, `SwitchboardUITests`.

## What to make
1. **A Switchboard is one row that scrolls sideways**, on every platform. Its switches in the board's order
   (unchanged), tiles the size they are in the grid, the dashed **Add switch outline as the last tile at the right
   end of every board's row** (it adds to that board; the header's "+" goes, "Add Switch…" stays in the header's
   menu). Whenever there is more to the right, the next tile shows at least a quarter of itself at the trailing
   edge, on every width (so it is plain that the row scrolls), and the row comes to rest on tile edges. On the Mac
   a row that overflows also scrolls by trackpad and shift-wheel and shows a small chevron at an end while the
   pointer is over it. A board with no switch is its Add switch outline alone. The row keeps its place when a
   switch flips; when a switch is added the row scrolls to show it.
2. **The board itself: a panel.** Each Switchboard sits on one quiet surface of its own (the design system's
   card surface and hairline, `Support/DesignSystem`), which holds its header, its lights and its row, so the
   switches read as mounted on one board. Give it a little of the circuit: one thin trace that runs from the
   lights along behind the row and joins the tiles, or the like. Mild: nothing that competes with the switches,
   nothing skeuomorphic, no new colours. Loose switches have no panel.
3. **The lights**: a strip of small dots in the panel's header, one a switch, **in the row's order**, each green
   (on) or red (off, due) in the Flipboard's own two colours (`FlipLights`), always in view however far the row
   has scrolled. It replaces the "3 of 5" text (the cadence line stays). When every switch is on, the board says
   so at a glance without words (the strip, and the trace if you draw one, wholly green; a board with a red is
   plainly not). Tapping a light scrolls the row to its switch. **The backup when dots do not fit** (decide by the
   width the header really has, not by a fixed count; test with 3, 12, 20 and 40 switches): the same strip as
   slimmer segments, one a switch, still in order; and past what even that fits, a two-tone bar with the count
   beside it ("17 of 24"). Never two lines, never truncated dots. With Differentiate Without Color on, red and
   green differ in shape as well. VoiceOver reads the strip as one element: "3 of 5 on. Off: Brush teeth, Floss."
4. **The ungrouped switches fold away.** They stay at the top, in the grid, two across on iPhone, with their Add
   switch outline last. When there is at least one Switchboard, a header in the section-header style sits over
   them (George's word: "Ungrouped"), with the same lights and a chevron; tapping it folds the grid away to that
   one line and back. Folded is remembered on this device (`AppGroup.defaults`; no schema change), and adding an
   ungrouped switch from the menu unfolds it. With no Switchboard there is no header and nothing folds.
5. **The jitter when a switch is added on iPhone.** Reproduce it first on an iPhone 16 simulator and film it
   (add a switch to the grid and to a board, with and without a time, with a long name that wraps); find the cause
   rather than damping the symptom (suspects: `SwitchLanding`'s spring running while the grid's own animation and
   `scrollTo` run; every tile taking the tallest's height as the new one measures; the query delivering the insert
   twice). After your fix a new switch appears once, in its place, and no other tile changes size at all; one soft
   settle on the new tile at most. Put a before and after strip of frames in your folder, and pin what you can in
   a test.
6. **The cards.** On iPhone the cards float as they do. On the Mac and iPad the switch card and the Switchboard
   card still open in place; decide where "in place" is for a switch in a row (in the row, the row scrolled so the
   whole card shows, or directly under the row) so that nothing jumps and the click-away, Esc and Discard rules
   (`BoardInlineAdd`) hold as they are.
7. **Dragging** a switch onto a board's panel, or off it to the ungrouped grid (also when it is folded: the header
   takes the drop), works as before; VoiceOver's Move to… too.

## The look, and proving it
- Everything from `HITColor`, `HITType`, `HITSpacing` and the design system's cards; all eight themes; Dynamic Type
  up to the largest accessibility size without overlap or truncation (the header may wrap its cadence line under
  the name; the lights stay on one line).
- Pictures in `126-flipboard-rows/` in the notes folder, from the running app, not mock-ups: iPhone 16 (two boards
  and ungrouped switches, open and folded; one board all green; a board of 20; adding a switch), the Duo's outer
  display, an iPad or the Duo's inner display, the Mac (light and long rows; the card open in place). **By 60
  minutes send the supervisor the first two or three of these** (the panel with its lights on iPhone 16 and on the
  Mac) with one line on what you chose and what you rejected, and carry on.
- Simulators of your own, one booted at a time: `HITList-126-16` (iPhone 16), `HITList-126` (iPhone Duo; it boots
  folded on the outer display; `xcrun simctl io <udid> screenshot --display=primary`), an iPhone 17
  (`HITList-126-17`) for `scripts/test.sh ios` at the end; `xcrun simctl bootstatus <udid> -b` before a test run on
  a fresh one. A Debug Mac app of your own with `HITLIST_STORE_SUFFIX=s126` (`-disableCloudKit YES -seedDemoData
  YES -hideTips YES -ApplePersistenceIgnoreState YES`; `scripts/window-shot.sh`, `scripts/window-drive.sh`). Delete
  the simulators, quit the Mac app and unregister its extensions when you finish.

## Ownership
`HITList/Views/Flipboard/*`, `HITListTests/Flipboard*Tests.swift`, `SwitchboardTests.swift`,
`HITListUITests/FlipboardPhoneUITests.swift`, `SwitchboardUITests.swift`, the Flipboard's lines in
`QASweepUITests` and in `Views/Help/*` if they describe what you changed. Not the models, not `TaskActions`, not
the widgets, not `Support/DesignSystem/*` (if a token is missing, say so in the report and use the nearest).

## Done
- `scripts/test.sh core macos ios` green, and the two Flipboard UI test classes green on your iPhone 16 simulator
  (`xcodebuild test -scheme HITListUITests -only-testing:…`); counts before and after.
- The report COMMON asks for, with each of the seven items answered in a line, what you decided where this brief
  left a choice, and anything you could not see running.
