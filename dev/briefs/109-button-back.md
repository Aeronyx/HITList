# Brief 109: Button, back as he was; Button's and Nod's snow (0.9.6)

Read `dev/briefs/COMMON.md` (the Round 22 block first), then this. **Report due 07:20 Eastern.** Effort: high.

## George's words
On 0.9.5's pictures (2026-11-12): "Please completely revert to the previous mushroom creature, the new one is much
worse/much less unique. I actually kind of liked his creepy-but-slightly-endearing big-eyed smile and rosy cheeks.
His sleeping sprite was also great." And of the large black eyes three creatures share: "they fit best on the
mushroom (meaning the previous mushroom, not the new one, which we're scrapping)".

The evening before, of 0.9.4's Button, the one he now wants back: "Please don't be lazy and just have every creature
with feet swing their feet as a part of their idle animations; the new mushroom creature certainly shouldn't be
swinging his feet as he has tiny stubs for feet and it makes no sense for his character's vibe anyways. […] The new
mushroom should stand fully on top of the search bar and puff around or roll around, doing mushroom-related
animations".

## How the two are read together
The creature is 0.9.4's again, whole: the drawing, the size, the pale face on its stem with the big round eyes,
glints, smile and rosy cheeks, the boots, every weather still, and the sleeping sprite (the cap pulled down over its
eyes), **pixel for pixel**. "A bit large" and "kind of creepy" are withdrawn by "completely revert" and "I actually
kind of liked". What stays from round 21 is what was never about his look and has not been withdrawn: **no boot
swinging**, and he **stands on top** of what he is on.

## What is there
- 0.9.4's Button: `git show v0.9.4:HITList/Support/Companions/Characters/Button.swift` (a copy is
  `103-button-stands/workshop/Button-before.swift` in the notes folder), its tests
  `git show v0.9.4:HITListTests/CompanionButtonTests.swift`, its workshop `102-rose-and-graphite/` in the notes
  folder. 20 × 20, `seatRow: 18`: the boots hang two rows over the edge.
- Master's Button (0.9.5): the small redraw with the bob, the puff, the roll, the spores, and round 21's tests.
- The format moved after 0.9.4 (idle weights and loops, the island seat on the Duo, `CompanionCastFlavorTests`: feet
  may be at most a fifth of a creature's idles, `CompanionSeatTests`): the 0.9.4 file may not pass as it is. Bring
  it to today's format without changing a pixel of a still.

## Items, in this order, one commit each
1. **The creature back.** Every still of 0.9.4 (`rest`, rain, heat, asleep and its weather, in both postures)
   identical to `v0.9.4`'s rows: a test pins it (a digest of each still's rows, computed once from the tag, is
   enough). The snow stills are item 4. The swatch in Settings shows him as 0.9.4 did.
2. **He stands.** The drawing does not change; the seat does: the soles of his boots on the top edge of the bar
   (the "+", the Mac's search field, the Duo's tab island, the swatch's card), nothing of him over its face. If the
   format cannot seat a sprite whose last row stands on the host, keep one row over the edge (the soles), never
   two, and say so. Check the "+"'s curve (`CompanionSeatTests`, `seat.py`): no gap of window under a boot.
3. **A mushroom's idles.** 0.9.4's idles and loops minus every swing and kick of a boot. In their place, drawn on
   the 0.9.4 body at its size: a wobble of the cap; a bob (the cap squashes a pixel and springs back); a puff
   (cheeks out, the cap lifts a pixel, a breath out); two or three spores let go from under the cap that drift up
   and fade. Take what carries over from master's Button. 0.9.4's routines that were already a mushroom's stay (the
   stretch that lifts the cap off, the wobble, the sneeze of one spore, nodding off under the cap, the parasol
   spin). The roll along the bar only if everything else is done and it looks right at this size. Boots: zero.
4. **Button's snow**, to COMMON's recipe (inks `s`, `b`, `c`). A dusting on a cap this round is the easiest snow of
   all to read as a hat or as icing: keep it to the crown and the far shoulder of the cap, ragged, blue under
   white, the spots still showing through at every depth; his shake-off (the cap tipped, the heap sliding off)
   redrawn over the new pile.
5. **Nod's snow** (`Characters/Nod.swift`, the snow frames only: `snow`, `snowDeep`, asleep's, and what is carried
   or drawn onto them; workshop `105-cast-flavor/workshop/nod_new.py` and `84-companion-routines/workshop`). Nod
   already wears a cap: the snow must read as snow fallen on a cap and a shoulder (a dusting along its top and on
   the bobble, a drift to one side), not as a second, white cone.

## Ownership
`Characters/Button.swift`, `HITListTests/CompanionButtonTests.swift`, Button's line in `ThemeCompanion.seats`,
Button's and Nod's cases in the shared companion tests, and Nod's snow frames in `Characters/Nod.swift` (nothing
else of Nod's). Not yours: the other creatures, the engine, the ink table.

## Done
- A sheet, looked at by you at 1x, 2x and 3x on the "+" (Rosé) and on the Mac's field: 0.9.4, 0.9.5 and now, side
  by side, awake, asleep, each weather, each snow depth; strips of the new idles; Nod's snow before and after.
- The identity test; `scripts/test.sh macos` green once at the end (the supervisor runs iOS and the UI suite).
- The report COMMON asks for, with the pictures' paths in `109-button-back/` in the notes folder.
