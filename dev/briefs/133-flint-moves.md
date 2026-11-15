# Brief 133: Flint's blink, his rain, and his other drawings (session `flint-moves`, effort xhigh)

George, 2026-11-14, on 0.9.9 (the first build with Flint; `Characters/Flint.swift` on master is what he has):

> Both Flint's rain animation and blinking animation are a bit weird. My friend overall likes Flint though so don't
> change his actual character too much yet, just his animations and non-Day sprites.

Read `dev/briefs/COMMON.md` (the Round 27 block first, then Round 25's and Round 24's creature rules: the water
recipe, no single-pixel eyes, the format's limits, the sheet), `dev/briefs/ROUND-27.md`, `dev/briefs/128-flint.md`
and its workshop in the notes folder (`128-flint/workshop`), then `Characters/Flint.swift` and
`HITListTests/CompanionFlintTests.swift`.

## What stays
- **The daytime Flint, pixel for pixel**: frame `rest` and his face, body, tail and colours wherever a daytime
  frame shows them (`lookL`, `lookR`, `happy`, `chirp`, `ruffle`, the wings, `fly`…). First commit: a test that
  pins `rest`'s rows by digest, as `CompanionKeptTests` does for Hush. A friend likes him; this is the drawing
  that was liked.
- **Every frame, gesture and routine name.** 132 is building a cheer from his existing frames by name (`happy`,
  `giggle`, `wingsUp` and others) and 135 shows his `fly` frame on a theme box. Change what a frame draws; never
  rename or remove one. New frames may be added.
- The engine. If you think it must change, stop and tell the supervisor.

## What changes, in this order
1. **Say what is weird before you fix it.** Render today's blink (`blink`, `half`, the `slowBlink` and `twinkle`
   gestures) and today's rain (`rain`, `rainPeek`, `rainBlink`, `rainDuck`, `drip1`…`drip5`, the `peek` and `duck`
   routines) tick by tick at 1x and 3x on the "+" in Graphite, beside Hush's and Quill's blinks and Quill's and
   Nod's rain. One sentence each on what reads wrong at real size. The supervisor will send you its own notes in
   your first minutes; where they and your eyes disagree, show both.
2. **The blink.** His eyes are a 2 × 2 pupil in a ring of light. A blink has to read as lids closing over those
   eyes and opening again, at 1x, in two or three ticks: nothing that makes the face go blank, nothing that makes
   the eyes jump in size or place, no flash of white. Candidates on the sheet.
3. **The rain.** Today he raises a wing over his head and the drips run. Make the still read as Flint sheltering
   under his own wing (it must read as a wing, not a hood or a ring around his head), keep the water recipe
   (beads that stay, a drop that runs off and falls, a puddle on the flat of the "+", every whole rain frame
   carrying the water, blue only), and make what moves in it smooth: no frame in the drip or the peek where his
   head or wing jumps and comes back. The storm's `duck` follows the same pose.
4. **The drawings that are not the daytime one**: asleep (`sleep` and its breaths), asleep in the rain
   (`sleepRain` and its drips), and the snow frames only where they must follow a change above. Asleep he must be
   the same animal: the same head (its width, its ears, its beak showing, as round 25 decided), settled low, eyes
   shut as lids over the same eyes. Judge each beside `rest` at 1x: if a stranger would not say "the same
   creature, asleep", it is not done.
5. **Then the tests**: his frames within the format (a small gesture changes 16 pixels at most), the water
   recipe's checks, the seat tests (his puddle on the flat of the "+").

## The sheet (due 20:55 Eastern)
Before and after at 1x, 2x and 3x on the "+" in Graphite and once on the Mac's field: the blink as a strip, the
rain still and its drip as a strip, asleep, asleep in the rain; and the line-up of all eight at 1x by day, asleep
and in the rain with your Flint in it (`round-25/draw/cast.py`). Two or three candidates where you are unsure,
your pick marked, one line of why. Send the supervisor its path and carry on with your pick; it goes to George at
once.

## Ownership
`HITList/Support/Companions/Characters/Flint.swift`, `HITListTests/CompanionFlintTests.swift`, Flint's own cases in
the shared companion tests. Nothing else: not the engine (132), not `ThemeCompanion.swift` (135), not another
creature's file.

## Done (report due 21:40 Eastern)
Draw first and build once, late: no simulator; `scripts/test.sh macos` green, and one look at him in a Debug Mac
app of your own (`HITLIST_STORE_SUFFIX=s133`, `-companion flint`, the launch arguments that force night, rain and
snow) if the clock allows. The report COMMON asks for, with every frame you changed listed and a sentence that no
daytime frame's pixels changed (or exactly which did and why).
