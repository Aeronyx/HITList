# Brief 23: Mac popout pickers inside the window: a HITList calendar, time and reminder pickers

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first (especially "Where things stand" and the
round-5 ownership below), then `HITList/Views/Popouts/PopoutPickers.swift`, the chip rows of
`QuickAddPopout.swift` (`.popover(isPresented: chipBinding(…))`, seven of them) and `TaskPopout.swift`
(three), `HITList/Support/DesignSystem/README.md` (components, `hitGlass`, `HITMotion` roles), and
`HITList/Views/Upcoming/WeekStripView.swift` (the one calendar-like view we already draw).

## Why (George, 2026-11-01, after build 6 on the Mac)
"The 'Add task' popout on Mac looks incredible; that should be your standard for the app. Some issues
with it still are that … the UIs for the Date calendar and Reminders subtabs are lazy and shouldn't
regularly exceed the bounding box of the app itself." Their screenshot: the Date chip's popover (Today /
Tomorrow / Next week / No date chips, the system graphical `DatePicker`, a Repeat chip) hanging out past
the window's edge. The system `DatePicker` and `NSPopover` are the two things to replace.

## Files you own
`HITList/Views/Popouts/PopoutPickers.swift`, new files under `HITList/Views/Popouts/Pickers/`, a new
`HITList/Support/DesignSystem/HITCalendar.swift` (and its README section and gallery entry in
`DesignSystemGallery.swift`), the chip `.popover` call sites and `chipBinding` plumbing in
`QuickAddPopout.swift` and `TaskPopout.swift` (nothing else in those two files), `HITListTests/PopoutTests.swift`,
new `HITListTests/PickerTests.swift`, and the ROADMAP row named below. Not yours: `PopoutHost.swift`,
`PopoutController.swift`, `QuickAddDraft.swift`, `TokenHighlightField.swift`, `Models.swift`, `HITTokens.swift`.

## Know before you start
- The Mac popout is a 560 pt panel (`PanelBackdrop`) near the top of the window; the iPhone card is an
  oval above the keyboard; the task popout is a panel on the Mac and a sheet on iPhone. Chips are
  `HITChip`/`HITChipLabel` (`size: .compact` in the quick-add bar). Every picker today is a SwiftUI
  `.popover`, which on the Mac is an `NSPopover` that may extend past the window, and on iPhone becomes a
  sheet.
- Motion: `HITMotion.enter`/`exit` for appearing and leaving, `quick` for hover. Glass: `hitGlass(in:
  tint:fallback:fallbackShadow:)`; honour Reduce Effects through `@HITEffectsSetting`.
- `DateExpressionParser` (HITListCore) does the date math; `Preferences.weekStartWeekday()` is the week
  start the user chose (Settings → General). `WeekStripView` already draws weekdays in Inter.
- Keep every existing token behaviour: picking writes the token into the title text (`Today`, `tom 11am`,
  `!15mb`, `every week`), the same as now. Tests in `PopoutTests` pin that; keep them green.

## Task, in commits
1. **`PickerPresenter`: an in-window anchored overlay.** A modifier `pickerAnchor(_ kind:, isPresented:,
   content:)` that records the chip's frame with `anchorPreference`, and a `pickerOverlay()` applied once
   at the popout's root that draws the open picker card over the popout, below its chip (above it when
   there is no room), horizontally clamped so the card never leaves the window, with a soft shadow,
   `Theme.surface` (or `hitGlass` when effects are allowed), 1 pt `Theme.separator` border, 14 pt corners.
   Click outside, Escape and picking all close it; Tab moves into it. `enter`/`exit` motion. On iPhone the
   same pickers present as today's sheets (don't change the iPhone's presentation in this brief; the
   overlay is a Mac/iPad thing), so `pickerAnchor` falls back to `.popover`/sheet on compact width.
2. **`HITCalendar`.** A month grid in Inter: month name + year, ‹ › and a "today" dot like the system's but
   ours; weekday initials in `Theme.secondaryText`; days as 32 pt circles, today ringed in accent, the
   selected day filled accent with `HITColor.onAccent`, other-month days dimmed, past days slightly dimmer,
   hover `quick`; arrow keys move the selection, Return picks; respects `weekStart`. Pure layout helpers
   (`HITCalendar.weeks(for:month:weekStart:calendar:)`) unit-tested for January/December, leap years and
   both week starts.
3. **Date picker card.** Presets row (Today, Tomorrow, Next week, Weekend, No date), the `HITCalendar`,
   a time row (`HITField`-styled "9:00 AM" text that accepts "9am", "17:30", "noon"; parse with
   `DateExpressionParser.matchTime`; a × clears the time), and the Repeat row. Everything inside the 560 pt
   panel's width; the card itself is about 320 pt wide.
4. **Reminder picker card.** The offsets (At time, 5, 10, 15, 30 min, 1 hr, 1 day before) as `HITChip`s,
   two per row, plus a custom "N minutes before" field; shows the resulting fire time ("Fires 10:45 AM").
5. **Priority, Group, Labels, Deadline, Repeat, Location** move onto the presenter too (same content as
   today, re-laid out in the card width, no system `List` chrome).
6. **Tests.** `PickerTests`: calendar grid maths, clamping maths for the presenter (pure function:
   `PickerPlacement.frame(anchor:cardSize:bounds:)` keeps the card inside and below/above), time text
   parsing in the time row. Existing `PopoutTests` green. `scripts/test.sh core macos` after each commit,
   `ios` before the last.
7. **ROADMAP.** Add one row to the second table: "Mac pickers inside the window (HITCalendar, time and
   reminder cards)" with status and what you verified.

## Verify running
Build and run the Mac app (`xcodebuild build -destination 'platform=macOS'`, then open the product) and
describe what you see in words: open the quick-add panel (⌘N), click each chip, confirm the card stays
inside the window at the window's minimum size (760 × 560) and at a narrow-but-legal width; then the
task popout's chips. You cannot screenshot the Mac; the tests and your description are the record. Check
the iPhone 17 simulator once to confirm the chips still open their sheets.

## Report
What changed per commit; test counts before and after; the Mac description; the branch name; anything
George must decide (for example whether the presets row should include "Weekend").
