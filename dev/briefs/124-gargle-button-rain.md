# Brief 124: water on Gargle and Button; Gargle under deep snow; Button on his swatch's floor (0.9.8)

Read `dev/briefs/COMMON.md` (the Round 24 block first: the water recipe is there), then this. **Sheet due 25
minutes after you start, report 85 minutes after you start.** Effort: xhigh.

## George's words (2026-11-12, on 0.9.7)
"For all creatures: Their rain interactions don't make much visual sense, as the rain is both not blue enough to be
clear that it's rain and also many of the characters don't even get rain on them to begin with. During rain, they
should have little droplets bead off of them every once in a while, and have some droplets stick around or tiny
puddles pool around their feet so it's clearer why they're cowering/hiding."

"Gargle: much better. Can be largely left alone for now, but perhaps not perfect. He looks barely recognizable in
deep snow, though."

"Button: done for now; just have him sit at the bottom of his square box in the Theme settings menu for variety's
sake."

## What is there
- **Gargle** (`Characters/Gargle.swift`, Graphite; brief 117): awake he is his night sprite with the eye open, in
  profile, snout to the left. In rain his wing curves over his head (`rain`, the moves `peek` and `duck`): no water
  on him, none at his feet. Asleep he has no rain still. At `snow3` (and `snow2`) the powder lies over his brow,
  between and over his horns, on his snout and wing: at real size the profile is gone and he is a grey lump with
  white on it. His asleep stills are pinned by a test (the night sprite George adores).
- **Button** (`Characters/Button.swift`, Rosé; 0.9.4's drawing, pinned): in rain his cap is pulled down to his
  cheeks, eyes peeking under the rim. No water on the cap, none at his boots; asleep he has no rain still.
- **Settings → Appearance**: each theme's swatch shows its creature (`Views/Settings/ThemeCompanion.swift`,
  `seats`, `Placement`). Nod, Tuck, Glim and Button all sit `.onCard` at the same spot: four of eight alike.

## What to make
1. **Gargle's rain, wet** (COMMON's recipe): beads along the top of the wing that shelters him, one hanging at the
   wing's tip, one on his snout; the drop that runs off falls from the wing's tip; a puddle at his feet on the side
   the drop lands. Asleep in the rain: a new still, the night sprite with his wing a little over him if it reads
   (else as he is), beads on the wing and back, the puddle; `sleep` itself does not change by a pixel.
2. **Gargle under deep snow, still Gargle.** Redraw `snow2`, `snow3` (and `sleepSnow2` if it has the same fault)
   so that at 1x beside `rest` nobody doubts who it is: both horn tips, the brow line, the eye, the snout's tip and
   the wing's outline stay his own stone at every depth. The snow goes where it would lie on a statue: along his
   back and the wing's upper edge, a little in the hollow between the horns, a small drift against his feet on the
   bar; never across the brow or the eye, never the whole snout, never joining into one mass. Deeper means the
   drifts grow, not that more of him is covered. Round 22's powder recipe holds (three tones, ragged, no cap).
3. **Button's rain, wet**: beads on the cap's crown, a drop hanging at each low point of the pulled-down rim (they
   are his drips: one lets go now and then), a puddle round his boots. Asleep in the rain: a new still, his asleep
   pose with beads on the cap and the puddle. His rain still's digest in `CompanionButtonTests` changes: update
   it; the plain, heat and asleep digests do not.
4. **Button on the floor of his swatch.** A new `Placement` in `ThemeCompanion` (standing on the swatch's bottom
   edge, inside the box, his boots on its floor) and Button's seat set to it, placed so he clears the accent dot
   and the rounded corner and the grid's height does not change; the geometry tests extended. Look at the whole
   grid on an iPhone 16 width and on the Mac: the eight should now sit eight different-looking ways as far as the
   placements allow; change no other creature's seat.

## The sheet (25 minutes)
Gargle's and Button's rain stills (0.9.7 beside two candidates each) and Gargle's `snow3` (0.9.7 beside two
candidates), at 1x, 2x and 3x on the "+" in their themes and once on the Mac's field. Send the supervisor its path
and your picks with one line each, and carry on.

## Ownership
`Characters/Gargle.swift`, `Characters/Button.swift`, `HITListTests/CompanionGargleTests.swift`,
`CompanionButtonTests.swift`, their cases in the shared companion tests; in `ThemeCompanion.swift` the new
placement, its layout and Button's seat line, with `ThemeCompanion`'s tests. Nothing else: no plain, heat or
asleep frame of either changes.

## Done
- Before and after at 1x, 2x, 3x, strips of the drop running off, and the Settings grid before and after, in
  `124-gargle-button-rain/` in the notes folder.
- `scripts/test.sh macos` green at the end. The report COMMON asks for, saying which idles no longer play in the
  rain (if any) and that no frame outside this brief changed.
