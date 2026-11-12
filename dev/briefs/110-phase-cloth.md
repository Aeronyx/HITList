# Brief 110: Phase, a cloth ghost with eyes of its own (0.9.6)

Read `dev/briefs/COMMON.md` (the Round 22 block first), then this. **Concept sheet due 06:05, report due 07:20
Eastern.** Effort: xhigh.

## George's words (2026-11-12)
"I don't love that three of the characters have the same style of large black eyes (the bat, the mushroom and
Mocha); they fit best on the mushroom […], so perhaps change the eyes on the bat and ghost to be more custom. The
ghost (Phase) also looks like a Pac-Man ghost instead of like Shuppet. I've attached a picture of Shuppet, which I
understand you can't copy directly, but you can definitely be inspired by it. Phase also looks weird "behind" the
button as it just causes him to have a weird darker underside. He's a ghost anyways, it probably doesn't make sense
for him to be the "behind" character unless you can execute it much better."

"Phase should be largely unaffected by snow and rain given he's a ghost, so come up with something clever there."

## What is there
`Characters/Phase.swift` (20 × 20, `seatRow: 17`): a dome with a point, drawn in the accent (Mocha's mauve), a
little see-through (`seeThrough`), round black eyes with a glint, and a scalloped hem in the veil ink `v` lying over
the top of the "+": that band is the "weird darker underside", and the dome over an even scalloped hem is the
arcade ghost. Its routines lean on sinking into the "+". Tests `CompanionPhaseTests`; workshop and every picture of
round 20's Phase in `101-phase/` in the notes folder.

## What to make
**An original character.** George's picture is of a character that belongs to someone else; nothing of it is in the
repository or the notes folder, and Phase must not be it or be mistakable for it (`dev/SUPERVISOR.md` §7). What
George is pointing at is a family of idea, older than any game: a little cloth ghost, a soft doll made of a
handkerchief hung up by its head. Take that:
- **Cloth, not a dome.** A round hooded head, and under it a short body of hanging cloth that narrows a little
  below the head and falls open into two or three loose points of different lengths, with a fold or two shaded in
  (`r`), one corner lifted as if by a draught. Asymmetric and a little tilted. The point on its head stays Phase's
  own (the wisp that curls back, which George has seen and not faulted); do not give it another character's horn.
- **It hovers on top.** Awake and asleep, all of it is above the bar: the longest point of its hem just touches the
  top edge, as a cloth doll set down would. Nothing of it lies over the button's face, dimmer or otherwise, and
  nothing of it is behind. Going through the bar is a trick for a routine, and is drawn by leaving out what is
  below the edge (a ghost going through a wall), never by a darker band on the button. Asleep it may slump into a
  soft heap of cloth on the bar, its point flopped over.
- **Eyes of its own.** Not the round black eye with a glint (that is Button's from now on). Try: tall almond eyes
  that glow, pale (`l`) with a warm iris (`w`) and a small dark pupil or slit, under sly half lids; or eyes that
  are only light. George's standard still holds: a face that looks at you, a light in each eye ("soulless" is his
  word for eyes without one), cute beside Hush. A small sly mouth.
- **Its colours stay ours**: Mocha's mauve (the accent `a`) with `r` for folds and `l` for a sheen; a little
  see-through all over is fine and was liked. Not another character's blue-grey, not its three-colour eyes, not
  its outline: someone who knows that character may think "the same kind of ghost", never "that is it".

## Weather passes through a ghost
Nothing wets or covers it. Ideas to judge by drawing them, or better ones of yours:
- **Rain**: a drop comes down, goes in at the crown, shows lighter inside it for a frame or two (it is
  see-through) and leaves by the hem onto the bar; it watches the drop go by inside itself, or holds out a corner
  of cloth and the drop falls through that too. No beads, no shake-off.
- **Snow**: none settles on it. The flakes fall through and the powder gathers on the bar under its hem instead, a
  little drift that grows with `snowDeep` (to COMMON's snow recipe: `s`, `b`, `c`) while Phase hangs a pixel or
  two higher above it and looks down at it. At the deepest it does something a ghost would (dips through the drift
  and comes up with one flake on its point, which falls through; or blows the drift away), and the pile starts
  again. If the pile under it cannot sit where the format lets a sprite draw, say so and pick the next best.
- Thunder still makes it jump; heat may hang it limp like washing.

## Items, in this order
1. **A concept sheet by 06:05**: three designs, each awake and asleep, at 1x, 2x and 3x on the "+" in Mocha with
   Hush beside it for scale, and one of them on the Mac's field. Send the supervisor the sheet's path and your
   pick with one line of why, and carry on with your pick; the supervisor stops you only if it is the wrong one.
2. The stills: `rest` and asleep in both postures, the blink, then the small idles (a look, a sly smile, the point
   flicked, a corner of cloth lifting, a little bob up and down: it hovers).
3. The weather stills and their moves (above).
4. The routines and the flourish redrawn on the new body: keep those that carry over (vanishing for a blink and
   coming back grinning, the side-eye, the "boo", floating up and down, going through the bar and popping up
   further along); drop what only made sense with the veil. **Never a frame of the old Phase beside the new**: if
   time runs out, ship fewer routines, all of them new.
5. Its swatch in Settings (`ThemeCompanion.seats["phase"]`: today asleep on the accent dot; choose what suits the
   new drawing and fits the grid's height), the Duo's island seat, and the tests brought to the new drawing.

## Ownership
`Characters/Phase.swift`, `HITListTests/CompanionPhaseTests.swift`, Phase's line in `ThemeCompanion.seats`, Phase's
cases in the shared companion tests. Not yours: the engine and the ink table (the veil ink stays in the format for
the phasing trick; if the new drawing needs the engine to change, say what in a message and carry on without).

## Done
- The sheets and strips in `110-phase-cloth/` in the notes folder: old beside new at 1x, 2x, 3x on the "+" and the
  Mac's field, awake, asleep, each weather, each snow depth, all eight themes' inks once (it is drawn in each
  theme's accent).
- `scripts/test.sh macos` green once at the end. The report COMMON asks for, with what is original about it in two
  lines and what you would still improve.
