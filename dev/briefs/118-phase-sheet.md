# Brief 118: Phase, a floating sheet (0.9.7)

Read `dev/briefs/COMMON.md` (the Round 23 block first), then this. **Sheet due 30 minutes after you start, report
80 minutes after you start.** Effort: xhigh.

## George's words (2026-11-12, on 0.9.6)
"Phase doesn't look that great yet; his eyes and mouth are pretty weird, and he shouldn't have hands, he should
just have a wavy body that almost looks like a floating sheet. His horn makes him look like Casper, which is not
right. Try again."

Before that (on 0.9.5, still standing): "The ghost (Phase) also looks like a Pac-Man ghost instead of like
Shuppet. I've attached a picture of Shuppet, which I understand you can't copy directly, but you can definitely be
inspired by it. Phase also looks weird "behind" the button as it just causes him to have a weird darker
underside." "I don't love that three of the characters have the same style of large black eyes […] they fit best
on the mushroom". "Phase should be largely unaffected by snow and rain given he's a ghost, so come up with
something clever there."

## What is there
`Characters/Phase.swift` on master (0.9.6, brief 110), built whole by `110-phase-cloth/workshop/build.py` from
parts in `gen.py` (notes folder). In the app, enlarged (`round-23/study.png`): a round head with a curled point (the
"horn"), pale almond eyes with pupils set toward the middle and a "v" mouth (the "weird" face), and under a
pinched neck a body with one corner sticking out to the right and one down to the left: at real size a small
person running, the corner an arm with a hand. Asleep, a lumpy heap. What was right and stays: Mocha's mauve, a
little see-through, wholly on top of the bar with nothing over the button, weather passing through.

## What to make
**One shape: a sheet, floating.** Think of a small cloth dropped over nothing and hanging in the air:
- **No head and body**: one continuous drape, rounded at the top, a little wider toward the bottom, 11 to 13 px
  wide and 12 to 14 tall, leaning a pixel or two as if drifting. The sides are soft S-curves, not straight.
- **A wavy hem**: three or four waves of unequal width and depth along the bottom, the last one trailing off to
  one side like the tail of a sheet in a draught. Not an even row of scallops (that was the arcade ghost).
  Nothing sticks out sideways above the hem: **nothing that can read as an arm, a hand or a leg**, in any frame.
- **No horn.** The top is the sheet's own round crown. (One variant on the sheet may try a small soft fold or peak
  that is plainly cloth; the default has none.)
- **It floats**: its hem hovers a pixel or two over the bar and never touches it at rest; it bobs. Folds are a few
  `r` pixels that follow the waves.
- **The face, simpler**: two eyes and at most a tiny mouth, set a little above the middle, well apart. Draw four
  faces on the sheet and judge them at 1x beside Hush and Button:
  1. tall dark ovals (2 × 3, in `k`), each with one small light at the bottom inside: holes in a sheet, soft;
  2. the same, with the top inner pixel cut so they tilt (sly) and no mouth;
  3. small glowing ovals (`l`) with a 1-pixel pupil low in each;
  4. sleepy half-moons.
  Not Button's eye (large, round, a glint at the top, cheeks under it), not three tones in one eye, no "v" mouth.
  The mouth, if any: one or two pixels, or a short soft curve.
- **Original** (`dev/SUPERVISOR.md` §7): a sheet ghost is everybody's; ours is mauve, see-through, with its own
  face. Not another character's horn, eyes or zigzag.

## Weather goes through it, a little more plainly
- **Rain**: drops fall through the sheet: a pale drop visible inside it for two or three frames, then out under
  the hem onto the bar. The still: the sheet unbothered, one drop caught mid-way inside, a small splash pixel on
  the bar under it. It may look up at them.
- **Snow**: flakes fall through and the drift gathers on the bar under it, clearly growing with each depth
  (COMMON round 22's recipe), the sheet hovering a pixel higher over a deeper drift; at the deepest it sweeps low,
  the drift puffs away, and it starts again. It never wears snow.
- Thunder: it flattens and darts; heat: it hangs limp, the hem's waves slack.

## Items, in this order
1. **A sheet by the half hour**: v0.9.6's still, then three bodies (wave shapes) × the four faces as small
   candidates, your best three combined at 1x, 2x and 3x on the "+" in Mocha with Hush beside it and one on the
   Mac's field, each awake and asleep (asleep: the sheet settled on the bar in soft folds, eyes shut, or hovering
   low and slack). Send the supervisor its path and your pick with one line of why, and carry on.
2. The stills, the blink and the small idles: a bob, a ripple along the hem, a look left and right, the sly look,
   a slow turn (the sheet swings round), a shiver that runs down it.
3. The weather stills and their moves.
4. The routines and the flourish that fit a sheet: vanishing for a blink and back, going down through the bar and
   up further along (drawn by leaving out what is below the bar's top), the "boo" (it swells), a loop-the-loop or
   a swoop. **No wave, no holding anything out, no frame of 0.9.6's Phase.** Fewer, all good, beats many.
5. Its swatch in Settings (`ThemeCompanion.seats["phase"]`, today asleep on the accent dot), the Duo's island
   seat, the tests.

## Ownership
`Characters/Phase.swift`, `HITListTests/CompanionPhaseTests.swift`, Phase's line in `ThemeCompanion.seats`, Phase's
cases in the shared companion tests. Nothing else; the engine stays as it is.

## Done
- Sheets and strips in `118-phase-sheet/` in the notes folder: v0.9.6 beside now at 1x, 2x, 3x on the "+" and the
  Mac's field, awake, asleep, rain, each snow depth, and the eight themes once.
- A test that no frame has a pixel run sticking out sideways from the body above the hem (your own definition,
  written down), so a hand cannot come back.
- `scripts/test.sh macos` green once at the end. The report COMMON asks for.
