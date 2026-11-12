# Brief 123: Quill's 0.9.6 face, a touch friendlier; Nod's eyes; Nod holds his canopy (0.9.8)

Read `dev/briefs/COMMON.md` (the Round 24 block first: the water recipe is there), then this. **Sheet due 25
minutes after you start, report 90 minutes after you start.** Effort: xhigh.

## George's words (2026-11-12, on 0.9.7)
"Quill & Nod: Actually, please revert Quill's face to the 0.9.6 version as it now looks out of place (with slight
modifications to Quill's 0.9.6 face to make him look a tad more friendly if you can, but be careful) and update
Nod's eyes as well, as that will lead us towards an art style where none of the characters have just single-pixel
dots for eyes. Be careful with Nod too please as I love his character and he's essentially done apart from his
eyes. Also for Nod, I thought his 0.9.6 design featured an umbrella over his head, which is what I wanted you to
have him hold; the new umbrella in 0.9.7 is terrible. Please either revert his rain sprite to 0.9.6 or turn the
thing above his head into an umbrella he's holding that rain can drip off for 0.9.8."

## What is there (`view.py` shows any frame; `git show v0.9.6:HITList/Support/Companions/Characters/<Name>.swift`)
- **Quill** (`Characters/Quill.swift`, Midnight). 0.9.6 (brief 112): the tabby, with a dark M on the brow, narrow
  bright eyes in the accent, a pale muzzle, a whisker pixel out to the side. 0.9.7 (brief 119) put 0.9.5's face
  on all 139 frames (two single dark pixels for eyes, no M): George: "out of place". 0.9.7's rain (ears laid back
  under the arched tail) and deeper snow are fine.
- **Nod** (`Characters/Nod.swift`, Slate): a round pale face under a nightcap with a bobble, legs over the edge.
  His eyes are one dark pixel each, low and wide apart. His plain drawing is otherwise finished.
- **Nod's rain**. 0.9.6: a small flat striped canopy with a peak, sitting over his cap (rows 0 to 3), nothing
  holding it: George took it for an umbrella over his head and liked it. 0.9.7 (brief 120): a one-pixel outline
  of a dome with a hooked wire down his left side, moves `twirl`, `gust`, `peek`, `duck`, and `sleepRain`:
  "terrible".

## What to make
1. **Quill's face is 0.9.6's again**, on every frame (the script from `119-tuck-quill/workshop` or
   `112-hush-quill/workshop` carries a face; or start from `v0.9.6`'s file and carry 0.9.7's rain and snow over:
   your call, the result is what matters): the accent eyes, the M, the muzzle, the whisker, pixel for pixel.
   Then, **"a tad more friendly … be careful"**: on the sheet, 0.9.6's face exactly, and three candidates that
   each differ from it by at most four pixels at `sit`: (a) the two inner strokes of the M, which slant down
   toward the nose and read as a frown, softened (one shade lighter or a pixel shorter); (b) the eyes a pixel
   rounder, each with a light; (c) the hint of a mouth turning up under the nose. The supervisor picks with you
   and may say "0.9.6's exactly". No eye of his is a single pixel.
2. **Nod's eyes.** The supervisor is drawing these itself and will send rows within about half an hour of your
   start. They will be the smallest step up from a dot that keeps him Nod (the same place, low and wide apart,
   still dark and simple). Carry them to every frame where his eyes are open (the blink, the glances, the looks
   up and at his light, every weather), and leave his asleep eyes and everything else about him alone. At 1x
   beside 0.9.7's `rest` he must be Nod at once.
3. **Nod holds his canopy.** The supervisor will send rows for this too. The thing above his head is **0.9.6's
   canopy** (take its pixels from `v0.9.6`'s `rain` frame, stripes and peak), now plainly an umbrella he holds: a
   one-pixel shaft from under the canopy down beside his face to his little hand, his arm out to it, on the side
   away from his bobble. Nothing else of 0.9.7's umbrella survives: no outline dome, no hooked wire. In the water
   inks (COMMON's recipe): beads on the canopy, a drop hanging from a tip of its rim that lets go now and then,
   a puddle at his feet where it lands. His moves in the rain, few and good: the drop; he tips the canopy and the
   beads run off one side; he peeks out from under it at the sky. Asleep in the rain: the canopy still over him,
   its shaft tucked in his arm, beads, the puddle. Thunder: he ducks under it.
4. **Quill's rain, wet** (COMMON's recipe): beads on the arched tail and his back, the drop off the tail's tip
   recoloured to water, a puddle at his feet; asleep in the rain a new still (curled or draped, tail over his
   nose, beads, the puddle), in both places.

## The sheet (25 minutes)
Quill's face (0.9.5's, 0.9.6's, 0.9.7's, the three candidates) and Quill's rain; then, when the rows have come,
Nod's eyes and his held canopy beside 0.9.6's and 0.9.7's; each at 1x, 2x and 3x on the "+" in its theme and once
on the Mac's field. Send the supervisor its path and your picks with one line each, and carry on.

## Ownership
`Characters/Quill.swift`, `Characters/Nod.swift`, their own test files, their cases in the shared companion tests.
Nothing else.

## Done
- Before and after at 1x, 2x, 3x and strips of the rain moves, in `123-quill-nod/` in the notes folder.
- `scripts/test.sh macos` green at the end. The report COMMON asks for, saying which idles no longer play in the
  rain (if any), how many of Nod's frames changed and that nothing but his eyes and his rain did.
