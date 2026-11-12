# Brief 128: Flint, a cartoon gryphon cub for Graphite, in place of Gargle (0.9.9)

Read `dev/briefs/COMMON.md` (the Round 25 block first; Round 24's water recipe and Round 22's snow recipe hold),
then this. **Concept sheet due 25 minutes after you start; report 125 minutes after you start.** Effort: xhigh.

## George's words (2026-11-12, on 0.9.8)
"We must iterate on Gargle once more; he's the only creature that doesn't fit the theme. He needs to have more
cartoonish eyes and appearance (not necessarily sillier, just less real), and perhaps make him a Gryffin or
something more fantastical instead of a straight dragon. Once you have him ready, make sure his weather animations
fit alongside the new ones we have now. (Also, please rename him; Gargle is a bad name)."

And, for Settings: "Put Gargle somewhere more interesting, like flying in the middle left slightly extended outside
of his box or maybe just in the bottom left of his box facing right, but definitely not behind his box; only Hush
should be hiding like that."

"Hush, Quill, Glim, and Button are all looking good along with the new weather effects."

## What is there
- The rename is done on master: the creature is **Flint** (`id: "flint"`, `Characters/Flint.swift`,
  `CompanionFlintTests.swift`). The file still holds Gargle's drawing: a stone dragon pup in strict profile, snout
  to the left, a small eye, a long snout, a folded wing, a haunch, 81 frames. Rounds 20 to 24 redrew him five times.
- **Why he does not fit.** Put the eight side by side at 1x (`round-25/draw/cast.py` in the notes folder draws the
  line-up; the supervisor's `cast-rest.png` is beside it). The other seven are cartoons: a head as big as the body
  or bigger, facing you or three-quarters on, two eyes that are each several pixels, a silhouette of a few flat
  tones, and one idea each (Nod's nightcap, Tuck's pot, Hush's ears, Glim's lantern, Phase's sheet, Button's cap,
  Quill's striped tail). Gargle is a small illustration: a profile, one small eye, a muzzle, shaded stone, anatomy.
  That is what "less real" means. It does not mean sillier.

## What to make
A **gryphon cub**: an eagle chick's head on a lion cub's body, drawn as the others are drawn.
1. **The concept sheet (25 minutes).** Five or six candidates for `rest`, each on the "+" in Graphite at 1x, 2x
   and 3x, **and each once in the line-up of all eight at 1x** in Gargle's place: the test is whether a stranger
   would say the eight were drawn by one hand. For example: (a) facing you: a round head with two feathered ear
   tufts, two large eyes (each at least 2 × 2, dark with a light in it; not Button's big round black eyes, which
   are his alone), a small hooked beak in the warm ink, a pale chest ruff, small folded wings at the shoulders,
   stubby lion's paws, a tail ending in a tuft curled round to one side; (b) the same three-quarters on, as Quill
   sits; (c) with the wings half open like little arms; (d) rounder and owl-like; (e) a wild card of your own that
   is "more fantastical" and still not a dragon; and Gargle as he is, for the before. Graphite's inks: greys, `l`
   near white, and the warm `w` (a peach) with its glow `g`; the accent `a` is a cream almost equal to `l`, so use
   the warm for the beak and feet and leave the accent out (the format allows accent or warm, never both). The
   supervisor is sketching too and will send rows within about fifteen minutes of your start: they are a starting
   point. Send the sheet's path and your pick with one line of why; the supervisor forwards it to George at once
   and answers; carry on with your pick meanwhile.
2. **The whole creature**, on the pick: every frame, mode, posture and routine the engine asks of a companion
   (take the list from what `Flint.swift` has today and from a finished sibling such as `Hush.swift`: the stills
   for both places, the "+" and the Mac's field; blink, glances, the reply to a tap awake and asleep; asleep with
   its breath; heat; thunder). Fewer moves, all good: about ten idles and three routines that are his alone, for
   example: he preens a wing with his beak; he pounces on his own tail tuft and misses; he flaps hard, lifts a few
   pixels off the bar, hangs there surprised and lands. Asleep: curled with his beak under a wing, the tuft over
   his paws. His own eyes on every frame; no eye is ever a single pixel.
3. **The weather, like the others'** (George: "make sure his weather animations fit alongside the new ones"):
   - Rain, by Round 24's water recipe exactly: he shelters his own way (a wing held over his head is his, and worth
     keeping from Gargle), two to four blue beads that stay, a drop that runs off the wing's tip now and then, a
     small puddle at his paws on the flat of the "+", every whole rain frame carrying the water, blue only, and a
     rain still asleep.
   - Snow by Round 22's powder recipe at its three depths, awake and asleep: the drifts grow, his head and eyes
     never go under; then he shakes it off.
   - Heat: his own way of being hot. Thunder: he ducks.
4. **`fly`.** A frame named exactly `fly`: him in the air, wings up, body level, the whole of him inside the
   20 × 20, facing the way `rest` faces; and `flyDown` with the wings down, if a routine uses the pair. Brief 131
   seats him in Settings with `fly`, at the middle left of his box and a little outside it, turned to face into
   the box. Commit `fly` as soon as the pick is made and tell the supervisor the commit: 131 is waiting on it.
5. **Tests.** `CompanionFlintTests` pinned Gargle's night sprite to `v0.9.6`: those pins go (George has asked to
   move on), the tests of his moves are rewritten for the new ones, and `rest` and `sleep` are pinned by digest
   once the supervisor says the drawing stands. In the shared companion tests change only the lines that name
   Flint. The comment over `"graphite": "flint"` in `CompanionCast.swift` and the doc comment in `Flint.swift` say
   what he now is.

## Rules that decide ties
- He must be an original: nothing that is, or could be mistaken for, a character someone else owns.
- Judge at 1x, in the line-up, before anything else. What reads at 8x and not at 1x is not drawn yet.
- When your pick and a rule of the supervisor's disagree, say so on the sheet; do not quietly follow either.

## Ownership
`Characters/Flint.swift`, `HITListTests/CompanionFlintTests.swift`, Flint's lines in the shared companion tests,
the one comment in `CompanionCast.swift`. Not `ThemeCompanion.swift` (131 owns every seat, his included), not the
engine, no other creature.

## Done
- The sheet, then before and after at 1x, 2x and 3x, the line-up of eight at 1x by day, asleep, in rain and in
  deep snow, and strips of each routine, in `128-flint/` in the notes folder.
- `scripts/test.sh macos` green at the end; one look in a Debug Mac app of your own (`HITLIST_STORE_SUFFIX=s128`)
  on Graphite by day, at night, in rain and in snow, then quit it.
- The report COMMON asks for, with the count of frames and which idles play in each weather.
