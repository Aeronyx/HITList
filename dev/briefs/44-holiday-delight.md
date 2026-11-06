# Brief 44: holidays and rare surprises (branch `holiday-delight`, effort High)

Read `briefs/COMMON.md` first. Six sessions run at the same time; see COMMON's "Round 10 ownership".

George's backburner notes, 2026-11-04:

> Automatic holiday events and themes would be neat! Maybe task completions drop snowdust around Christmas or
> explode in mini-fireworks on July 4th.

> Silly random events, like Nyan Cat flying across the screen with a 1/10000 chance on task completion.

Nyan Cat is someone else's copyrighted character: do not draw it or anything recognisably it (a cat with a pastry
body and a rainbow trail). Make an original rare visitor in the same spirit instead: a small pixel-art creature of
your own design (a slate-blue comet-whale, a tiny rocket with a sparkle trail…) that crosses the top of the screen
in about two seconds. Say what you chose.

## Items (one commit each, failing test first where there is logic)
1. **Holiday calendar** (new HITListCore `Holidays.swift`, pure, test-first): which celebration a date falls in,
   US-centric with a window around each: New Year (Dec 31–Jan 1), Valentine's (Feb 14), St Patrick's (Mar 17),
   July 4th (Jul 3–4), Halloween (Oct 24–31), Thanksgiving (4th Thursday of November), Christmas (Dec 18–26), and
   the solstices/equinoxes if cheap. Tests across years, including Thanksgiving's moving date.
2. **Completion effects** (`Views/Delight/*`, new `Views/Delight/HolidayEffects.swift`): on completing a task during
   a window, a short particle effect from the checkbox: snow dust drifting down (Christmas), mini fireworks (July 4th,
   New Year), little hearts (Valentine's), leaves (Thanksgiving), a pumpkin/bat flutter (Halloween), clovers (St
   Patrick's). `Canvas` + `TimelineView`, ≤ 1.2 s, ≤ 60 particles, no per-frame allocations, drawn above the row,
   never blocking taps. Honour Settings → Delight's master toggle and Reduce Motion (then no particles, maybe a
   tinted checkbox), and the completion sound/haptic stay as they are.
3. **A quiet theme touch** during a window: the "+" oval or the Today title gets a tiny seasonal accent (a snowflake
   glyph, a pumpkin tint) — subtle; George scrutinises pixels. Toggle "Holiday touches" in Settings → Delight.
4. **The rare visitor** (new `Views/Delight/RareVisitor.swift`): on completion, 1 in 10,000 (`Preferences` toggle
   "Rare surprises", on), crosses the top of the window once; Reduce Motion skips it. A Debug-only launch argument
   (`-forceRareVisitor`, `-forceHoliday christmas`) to demo it, never in Release.
5. **Mac and iPhone** both: the same effects in list rows and on the Mac board cards.

## Ownership
New HITListCore `Holidays.swift` + tests; `Views/Delight/*` (+ new files), `Support/Delight/*`,
`Views/Delight/DelightSettingsSection.swift`; the call sites where completion motion starts (`TaskRow.swift` only the
overlay hook, one line if possible); tests new `HolidayEffectsTests`; `project.yml` only to add files; ROADMAP row
"Holidays and rare surprises (brief 44)". Not yours: `QuickAddEntry.swift` (39 owns Mac focus there; if the "+"
accent needs a line in it, report it), `UpcomingBoard.swift` (39: report the hook it should call).

## Done
All three suites green (core count up); iPhone simulator screenshots (or a short `xcrun simctl io recordVideo` clip)
of snow, fireworks and the visitor via the Debug launch arguments; the effects described for the Mac.
