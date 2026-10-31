# Brief 19: Flipboard: long-press edits, the faint-green lamp, and charging switches

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first (especially "Where things stand" and
"Round 3 ownership"), then `HITList/Views/Flipboard/*.swift` and the Flipboard section of `ROADMAP.md`.
Build only on the design system (`HITList/Support/DesignSystem/README.md`).

## Why (George, 2026-10-31)
"Allow 'Unset / Flip to Red' and other edits by tapping and holding the button. Have the light in the top
right glow a faint green instead of just turning off when complete. Add support for multistep tasks, such as
ones requiring several flips to light up all the lights, or charge a single light for the task to be
complete within that timeframe (e.g. go to the gym 3 times this week: the task resets weekly but requires 3
flips to 'charge up'). I want this to be very visually satisfying if possible."

## Files you own
`HITList/Views/Flipboard/*` (FlipboardView, FlipSwitchTile, RockerSwitch, FlipboardRules, FlipSound),
`HITListTests/Flipboard*Tests.swift`, the Flipboard section of `ROADMAP.md`. Nothing else: `TaskPopout`
(its "Add to Flipboard" row stays as is), `Models.swift`, `HITTokens.swift`, sounds and everything outside
`Flipboard/` belong to other sessions. No new generated sounds: George dislikes synthesised audio. Reuse
`flip.caf` (and `bubble.caf` if a completion needs one).

## Know before you start
- Model today: a Flipboard switch is a recurring task without a time carrying the `flipboard` label.
  Green = due in the future, red = due today or overdue; a flip moves `dueDate` to the next occurrence
  from the flip day (`Flipboard.dueAfterFlip`, `Flipboard.flip`). New switches start red ("Flip to start").
  `FlipSwitchTile` has a `.contextMenu` (Edit Interval…, Open Task, Remove, Mark Done) but the rocker
  `Button` takes the long press on iPhone, so the menu is hard to reach.
- Schema V2 (on master) added to `TaskItem`: `flipTarget: Int = 1` (flips needed per interval),
  `flipCount: Int = 0` (flips so far in the current interval), `flipPeriodStart: Date?` (when the current
  interval's counting began). Use exactly these; do not add fields.
- `Flipboard.intervalStart(due:rule:)`, `elapsedFraction`, `daysOverdue` exist in FlipboardRules.
- Fonts: `HITType` roles (Inter). Colours: `HITColor.dueToday` is the green, `HITColor.dueOverdue` the red.

## Task, in commits
1. **Long-press menu on the switch itself.** Long press (iOS) / right-click or long press (Mac) anywhere
   on the tile, including the rocker, opens the menu: "Flip back to red" (undo the last flip: due returns to
   the interval it was in, count goes down one; disabled when red and uncharged), "Edit interval…",
   "Flips per interval…" (1–10, `HITSegmented` or a stepper from the design system), "Open task",
   "Mark done", "Remove from Flipboard". The plain tap still flips. Haptic on the long press.
2. **Lamp.** When a switch is green (done for the interval) the top-right LED glows a faint green with a
   soft bloom instead of turning off; red stays as today. Reduce Motion: no pulse.
3. **Charging switches.** `flipTarget > 1` turns a switch into a charger:
   - Rules (`FlipboardRules`, pure, tested): while red, each flip increments `flipCount` (setting
     `flipPeriodStart` on the first) and plays `flip.caf`; when `flipCount` reaches `flipTarget` the
     switch charges: due moves to the next occurrence exactly as a single flip does today, `flipCount`
     stays at the target so the lights show full. When the next interval arrives (the switch turns red by
     the date rule), the count reads as 0 for the new interval (`flipPeriodStart` older than the interval
     start means "stale": treat as 0 and reset on the next flip). "Flip back to red" decrements. Extra
     flips while charged do nothing but a small bounce.
   - Look: N small lamps in a row across the top of the tile (N ≤ 10; for one lamp keep today's single
     LED). Each flip fills the next lamp with a spring pop and a glow that spreads to its neighbours; the
     final flip lights them all, the rocker snaps, and a brief bloom runs across the light bar. Draining
     at the interval boundary animates the lamps emptying right-to-left the first time the board shows
     the new interval. `keyframeAnimator` / `phaseAnimator`, respecting Reduce Motion.
   - Editor: `FlipSwitchEditor` (new switch and Edit interval) gets "Flips per interval" with a live
     preview tile. `Flipboard.createSwitch`/`setRule` take the target. Caption under the title reads
     "2 of 3 this week" while charging, "Done this week" when charged.
4. **Tests and docs.** `FlipboardRulesTests`: charging math (count up, charge at target, stale count after
   the interval boundary, undo), single switches unchanged (`flipTarget` 1 behaves exactly as before),
   sorting puts charging switches with red. ROADMAP Flipboard section: a paragraph on charging and the
   long-press menu, and the UI table row "Flipboard: long-press menu, faint-green lamp, charging switches"
   marked done.

## Verify
Signed iPhone 17 simulator build. Record a video: create "Gym" with 3 flips per week, flip it three
times (watch the lamps), long-press it and flip back to red, show a single switch still working and its
faint-green lamp. Mac build and tests green (`scripts/test.sh`). Report per COMMON.md.
