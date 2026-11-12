# Brief 121: Phase, a ghost you can see through, with eyes that glow (0.9.8)

Read `dev/briefs/COMMON.md` (the Round 24 block first), then this. **Sheet due 35 minutes after you start, report
110 minutes after you start.** Effort: xhigh.

## George's words (2026-11-12, on 0.9.7)
"Phase: almost there; os it possible to make him slightly transparent or at least more ethereal-textured? Messing
with his default opacity as well as having some of his animations involve shifting his opacity around would be a
great addition to his character. He also looks just slightly too generic; if you can, please make tiny adjustments
to his body (not his face!) to make him more unique or at least more detailed (such as better shading on his
waves/around him in general, but I really do like him so don't ruin him please). His snow sprite should also only
have one pile/mound of snow, not three weird looking ones. Actually, although I said "not his face", I meant the
style, not the color; making his eyes glow after making him slightly transparent might be really cool. Can you also
make Glim's tail glow in that case, if it's possible, or does "glow" in this context just mean clever use of
colors? In any case, yes, making Phase a cool, slightly-transparent ghost creature is definitely the vibe here."

And for every creature: the rain's water (COMMON, Round 24).

## What is there
- `Characters/Phase.swift` on master (0.9.7, brief 118): one drifting sheet, built whole by
  `118-phase-sheet/workshop/build.py` from parts in `gen.py` (notes folder; 149 frames): a rounded crown leaning
  two pixels, a wavy hem with a trailing tail to the left, hovering two pixels over the bar; folds in `r`; two dark
  2 × 3 eye-holes (`k`) with a light (`l`) low in each, a one-pixel mouth. George likes this shape and this face.
- `seeThrough: 0.25`: the engine draws his `a` and `r` at 0.75. Over the dark window that is only a slightly dimmer
  mauve: nobody sees that he is see-through. The veil ink `v` (drawn at 0.6) makes his `fade`/`gone` frames.
- Snow: three separate little heaps under him. Rain: pale drops inside him, one under the hem.
- The engine: `CompanionSprite` is one `Canvas` that fills each run of an ink at `character.opacity(ink)`, sized
  exactly to the sprite; `CompanionCharacter.seeThrough` is 0…0.5; a frame is `Frame(name:, rows:)`.
- Glim (`Characters/Glim.swift`, Tokyo Night): his tail ends in a lantern drawn in `w` with `g` round it. His
  frames are pinned by tests and belong to brief 125 this round.

## What to make
You are the one session in the engine this round. Keep every other creature's drawing identical, to the pixel.

1. **The engine: light and fade.**
   - **A real glow.** A character names the inks that give light (`glow:` in `CompanionCharacter(`, a set of
     inks, empty by default). Every run of such an ink casts a soft halo of its own colour: real light, not
     pixels, drawn over the creature's other pixels and under the glowing pixels themselves, which stay crisp
     squares. About one and a half sprite pixels of spread, strongest at the pixel; tune it by eye in the app on the
     "+", on the Mac's field and in the Settings swatch (half size). It must not be clipped at the sprite's edge
     (Glim's lantern hangs at the right edge, below the seat row), must not change the sprite's layout size or its
     tap shape, and must cost nothing when a character names no ink. A frame may dim or swell it
     (`Frame(…, light:)`, 1 by default) so a move can brighten or put out the light.
   - **A body that fades.** A frame carries how much of the body is there (`Frame(…, fade:)`, 1 by default; your
     naming): it multiplies the opacity of the inks `seeThrough` already thins and of the veil; eyes, glints and
     the weather's inks stay solid. A composite ("frame@still") takes its gesture frame's value. Widen
     `seeThrough`'s range if Phase needs more than 0.5.
   - With Reduce Transparency on, a see-through body is drawn solid and nothing fades below half; the glow stays.
   - Tests for each (`problems` knows the new ranges; a character with no glow and no fade draws exactly as
     before: pin that with the runs and opacities of two existing creatures).
2. **See-through, for the eye.** By default he must read as a ghost at a glance at 1x, on a still screenshot, in
   Mocha on the "+" and on the Mac's field: not "a mauve sheet, slightly dim". Use what reads: the body thinning
   from a fuller crown to a nearly clear hem (more levels than `a` and `v`: fade by row within the frame, or more
   see-through inks: your call), a hem that breaks into a soft checker, an aura no stronger than a whisper. A list
   row passing behind the "+" should show through him plainly. Do not bring him down over the button (round 22:
   "weird darker underside"): he still hovers wholly above the bar.
3. **His eyes glow.** The same two eyes in the same place and style (2 × 3, the small mark low in each), the
   colour turned over: lit, with the low mark dark (the pupil), and the engine's glow on them; they stay solid and
   bright while the body fades. The mouth stays. Asleep the eyes are shut and dark.
4. **Opacity in his moves** (replace or re-time moves he has; add few): his idle breath thins and fills him a
   little as he bobs; the phase: the body fades away from the hem up until only his two glowing eyes hang in the
   dark for a beat, then he fills back in from the crown down; the reply to a tap: a flicker, two quick dips; the
   flourish and the pass through the bar use the fade instead of the veil alone. Asleep he is fainter than awake
   and pulses slowly with his breath.
5. **The body, tiny touches** ("don't ruin him"): the outline within a pixel of 0.9.7's everywhere, the face
   untouched but for its colour. On the sheet, three candidates, each at most about a dozen pixels from 0.9.7's
   `rest`: (a) shading only: a lit edge along the crown's upper side in a paler tone, two or three folds that
   follow the waves and taper, the inside of the hem's far waves a shade deeper so the cloth curls; (b) (a) plus a
   tail that ends in a small curl or thins to a wisp of veil; (c) (a) plus one wave of the hem notched, uneven,
   his alone. Pick by which is most his own at 1x beside 0.9.7's without being a different ghost. (A paler accent
   needs an ink: add one to the engine if you use it, see-through like the body; he then has six of his own.)
   Carry the pick to every frame through `build.py`.
6. **Snow: one mound.** A single heap under him on the bar, round 22's powder in the three snow inks, growing with
   each depth, the sheet hovering a pixel higher over a deeper heap; never on him. His last-snow sweep puffs that
   one heap away.
7. **Rain goes through him, in blue.** The drops inside him and under him in the water inks (seen through his
   body, so a little dimmer inside), a small puddle under him on the bar where they land (COMMON's recipe: the
   puddle, the ripple when one lands, asleep too). He stays unbothered.
8. **Glim's lantern glows.** Add `glow:` to Glim's `CompanionCharacter(` call (the lantern's `w`; check every one
   of his frames that nothing else of his is in that ink) and look at it in the app awake, in his lap in the rain
   and asleep (asleep it is dim: a fainter halo or none). Change no row of Glim: brief 125 owns his frames.
9. His swatch in Settings, the Duo's island seat, `CompanionPhaseTests` (`testNothingSticksOutAboveTheHem` stays
   as it is), the shared companion tests.

## The sheet (35 minutes)
One picture, drawn as the app will draw it (the body's opacity over the real backgrounds: the window, a list row
behind, the "+", the Mac's field; the halo as a blur): 0.9.7's `rest`, then your see-through treatment with the
glowing eyes in the three body candidates, at 1x, 2x and 3x; asleep; and four frames of the phase (full, thinning,
eyes only, back). Send the supervisor its path and your pick with one line of why, and carry on. As soon as the
engine draws it, send one real capture from a Debug Mac app too (Phase, and Glim's lantern).

## Ownership
`CompanionCharacter.swift`, `CompanionSprite.swift` and what the glow and the fade need in the engine's other
files; `Characters/Phase.swift`; `HITListTests/CompanionPhaseTests.swift` and new engine tests; Phase's line in
`ThemeCompanion.seats`; Phase's cases in the shared companion tests; the one `glow:` argument in `Glim.swift`.
Not the ink table's water and snow colours, not any other creature's rows.

## Done
- Sheets, strips and real captures in `121-phase-ether/` in the notes folder: 0.9.7 beside now at 1x, 2x, 3x on
  the "+" and the Mac's field; awake, asleep, rain, each snow depth; the phase as a strip; Glim awake, in rain and
  asleep with his glow.
- `scripts/test.sh macos` green at the end (and `scripts/test.sh ios` once on a simulator of your own,
  `HITList-121`, since the engine changed; delete it after). The report COMMON asks for, with what you decided
  where this brief left a choice.
