# Brief 125: water on Hush and Glim, and nothing else of theirs (0.9.8)

Read `dev/briefs/COMMON.md` (the Round 24 block first: the water recipe is there), then this. **Sheet due 25
minutes after you start, report 75 minutes after you start.** Effort: xhigh.

## George's words (2026-11-12, on 0.9.7)
"For all creatures: Their rain interactions don't make much visual sense, as the rain is both not blue enough to be
clear that it's rain and also many of the characters don't even get rain on them to begin with. During rain, they
should have little droplets bead off of them every once in a while, and have some droplets stick around or tiny
puddles pool around their feet so it's clearer why they're cowering/hiding."

"Glim: done." "Hush: done for now."

## What is there
- **Hush** (`Characters/Hush.swift`, Nord): in rain his long ears are drawn up over his head into a hood (George
  has seen it since 0.9.4 and it reads). Any drips are in his own pale inks. Asleep he has no rain still.
  `CompanionKeptTests` pins every one of his 93 frames to `v0.9.6`.
- **Glim** (`Characters/Glim.swift`, Tokyo Night; brief 116): 0.9.5's drawing, his stills pinned. In rain he curls
  his tail in and holds his lantern in his lap to keep it dry (`rain`, the moves `peek` and `warm`). There is no
  water on him and none at his feet, so nobody can tell why he is holding it. Asleep he has no rain still.

Both are finished creatures. This brief adds water to their rain and changes nothing else: no plain, heat, snow or
asleep frame, no move outside the rain, no seat.

## What to make
1. **Hush's rain, wet** (COMMON's recipe): two or three beads on the hood (his ears), one hanging from the hood's
   lowest tip on one side; the drop that runs off falls from there; a puddle at his feet on that side. Asleep in
   the rain: a new still, his asleep pose with the ears over him if that reads at 1x (else as he sleeps), beads,
   the puddle. In `CompanionKeptTests` the digests of the rain frames you change are updated and every other frame
   stays pinned to `v0.9.6`; say how many changed.
2. **Glim's rain, wet**: he is getting rained on while he keeps his light dry. Beads on his ears and the top of
   his head, one on his nose or cheek; a drop runs off an ear tip; a puddle at his feet. **Never a drop on the
   lantern**: it is what he is protecting (in the move `warm` he may wipe one off it, if that is already what the
   move reads as; do not redraw the move). Asleep in the rain: a new still, his asleep pose curled round the
   lantern, beads on him, the puddle. His pinned stills: only `rain`'s digest changes.
3. Brief 121 adds a real glow to the lantern through one `glow:` argument in Glim's `CompanionCharacter(` call:
   leave that call's arguments alone, and do not put water in the ink the lantern is drawn in.

## The sheet (25 minutes)
Hush's and Glim's rain stills, awake and asleep (0.9.7 beside two candidates each), at 1x, 2x and 3x on the "+" in
their themes and once on the Mac's field. On Nord and Tokyo Night the "+" is itself blue: choose the tones of the
puddle so it reads as water on the button, not as part of it. Send the supervisor its path and your picks with one
line each, and carry on.

## Ownership
`Characters/Hush.swift`, `Characters/Glim.swift` (frames and modes), `HITListTests/CompanionKeptTests.swift`,
`CompanionGlimTests.swift`, `CompanionHushTests.swift` if there is one, their cases in the shared companion tests.
Nothing else.

## Done
- Before and after at 1x, 2x, 3x and strips of the drop running off, in `125-hush-glim-rain/` in the notes folder.
- `scripts/test.sh macos` green at the end. The report COMMON asks for, saying which idles no longer play in the
  rain (if any) and that no frame outside the rain changed (a count of frames changed and frames added, each
  creature).
