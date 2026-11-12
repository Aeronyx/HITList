# Brief 111: Gargle, more of a dragon (0.9.6)

Read `dev/briefs/COMMON.md` (the Round 22 block first), then this. **Concept sheet due 06:05, report due 07:20
Eastern.** Effort: xhigh.

## George's words (2026-11-12)
"Gargle looks like he's throwing up, but I don't mind all of his animations, his nighttime sprite is quite cute, I
like that he's side-on for some postures. Perhaps turn him into a bit more of a dragon with a different eye and
mouth style."

"I don't love that three of the characters have the same style of large black eyes (the bat, the mushroom and
Mocha); they fit best on the mushroom […], so perhaps change the eyes on the bat and ghost to be more custom."

## What is there
`Characters/Gargle.swift` (round 21, brief 104): a horned stone pup in Graphite's greys, his body side-on and his
face toward you, round black eyes with a glint, a broad nose, an open mouth with one fang and a warm pixel under
it (at real size that reads as something coming out of his mouth: "throwing up"), a folded wing, his tail behind
the bar with its spade showing (the format's "behind" layer: capital letters). His profile is his statue pose and
his sleep, which George calls cute. Tests `CompanionGargleTests`; workshop and pictures in `104-gargle-perched/`
in the notes folder (`concepts.png`, `concepts-2.png` show what was tried).

## What to make
A small stone dragon, still Gargle, still Graphite's own greys:
- **Dragon**: a short snout (a muzzle that sticks out, clearest side-on and three-quarter), two small horns swept
  back, a ridge of two or three little spines down the neck or back, the folded wing readable as a wing (a rib or
  two), the tail with its spade behind the bar as now. Chubby and young, not fierce.
- **The mouth**: closed at rest. A short line along the muzzle with the corner turned up, at most one tiny fang
  poking up over the lip. Nothing dark and open, nothing hanging or dripping below it, no warm pixel under it. A
  dragon's fire belongs in a move, not the still: one small puff of smoke that drifts up from a nostril, or a
  hiccup with a single ember that rises and goes out. It must never read as being sick: whatever leaves him goes
  up and away from the snout's end.
- **The eyes**: his own, not the round black eye (that is Button's from now on). A reptile's: an amber iris (`w`,
  the warm ink) with a dark slit or small pupil and a light in it, under a brow ridge that can lower (haughty,
  sleepy, pleased). Still a face that looks at you: George's standard is cute beside Hush, and an eye without a
  light in it is "soulless".
- **Keep**: the night sprite's charm (redraw it only as far as the new head requires, and show old beside new),
  the side-on postures, the perch, the tail behind the bar, the statue game, and his routines wherever the new head
  fits them. George: "I don't mind all of his animations".

## Items, in this order
1. **A concept sheet by 06:05**: three heads on the same body (how much snout, which eye, which mouth), each
   awake and asleep, at 1x, 2x and 3x on the "+" in Graphite with Hush beside it for scale, and one on the Mac's
   field. Include the still enlarged with the mouth's pixels marked: say what a stranger would take them for.
   Send the supervisor the path and your pick with one line of why, and carry on with your pick.
2. The stills: `rest` and asleep in both postures, the blink, the looks.
3. Every idle, loop, routine and the flourish on the new head (most change only at the head).
4. Weather: rain, heat, and **snow to COMMON's recipe** (`s`, `b`, `c`): on a stone creature snow sits beautifully
   and reads as snow if it follows him: a line of powder along the spines and the top of the snout, on the wing's
   upper edge and each horn's base, a drift in the hollow of his back; never one cap across the horns.
5. His swatch in Settings (peeking over the top: it needs his eye row), the Duo's island seat, the tests.

## Ownership
`Characters/Gargle.swift`, `HITListTests/CompanionGargleTests.swift`, Gargle's line in `ThemeCompanion.seats`,
Gargle's cases in the shared companion tests. Not yours: the engine (the behind layer is used as it is) and the ink
table.

## Done
- Sheets and strips in `111-gargle-dragon/` in the notes folder: 0.9.5 beside now at 1x, 2x, 3x on the "+" and the
  Mac's field, awake, asleep, each weather, each snow depth.
- `scripts/test.sh macos` green once at the end. The report COMMON asks for.
