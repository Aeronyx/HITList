# Brief 120: Nod holds his umbrella up; Button pulls his cap down (0.9.7)

Read `dev/briefs/COMMON.md` (the Round 23 block first), then this. **Sheet due 25 minutes after you start, report
65 minutes after you start.** Effort: high.

## George's words (2026-11-12, on 0.9.6)
"Snow and rain need to be slightly more obvious on most of these creatures (Nod should actually hold up his
umbrella for rain, Gargle might hide under a wing, Button might grab his mushroom hood and warp it down a bit,
attempting to hide (or something that makes more sense with his character), etc."

## What is there (look at `round-23/study.png` in the notes folder: the app, enlarged)
- **Nod** (`Characters/Nod.swift`, Slate): in the rain a flat striped canopy sits on his nightcap like a hat. It
  does not read as an umbrella, and he is not holding anything.
- **Button** (`Characters/Button.swift`, Rosé): 0.9.4's drawing, pinned by a test (his plain, rain, heat and
  asleep stills have digests in `CompanionButtonTests`). In the rain his cap sits a pixel lower: nobody notices.
- Their snow (round 22, brief 109): powder in the three snow inks; fine, a little faint.
Nod's and Button's plain drawings George has not faulted: **they do not change**. Only the weather does.

## What to make
1. **Nod holds an umbrella up.** A real one: a small domed canopy over his head, a shaft down to his hand, held a
   little to one side so his face and cap show under it. The sprite is 20 × 20 and his cap's top is near row 3:
   lower him nothing, draw the canopy in the rows above and beside his cap (it may be tilted, its shaft passing
   beside his head), drops beading on it and one running off a rib's tip. In the theme's own inks (the canopy in
   `d` with `l` ribs, or the warm ink for one detail: your eye). Moves: he twirls it a quarter turn; a gust tips
   it and he rights it; he peeks out to see if it has stopped. Asleep in the rain: the umbrella propped over him,
   leaning on his shoulder. Thunder: he ducks under it.
2. **Button pulls his cap down.** Both little hands on the rim, the cap dragged down over his eyes to his cheeks
   and bent at the sides where he holds it (the rim curls down past his face), his eyes peeking out from under,
   drops running off the rim's two low points. Now and then he lifts the rim a pixel to look out, sees rain, and
   pulls it back down. A mushroom does not mind the wet much: he may also tip his face up and catch a drop, as
   0.9.4's routine had it, but the still is the hiding one. The rain still's digest in his test changes: update
   it, and leave the plain, heat and asleep digests as they are.
3. **Their snow, a little clearer**: the same powder (COMMON round 22's recipe), about half as much again at each
   depth, never a cap or a cone. Nod: on his cap's slope and bobble, his shoulders, and at the deepest he pulls
   his cap down over his ears. Button: a real little drift on his cap that slides when he tips it; at the deepest
   his cheeks go redder (the `a` ink he has).

## Ownership
`Characters/Nod.swift`, `Characters/Button.swift`, `HITListTests/CompanionButtonTests.swift`, Nod's and Button's
cases in the shared companion tests. Not their plain stills, not their idles, nothing else.

## Done
- **A sheet by 25 minutes**: Nod's and Button's rain stills, v0.9.6 beside two candidates each, at 1x, 2x and 3x
  on the "+" in their themes and one on the Mac's field. At 1x the umbrella must read as an umbrella and the
  pulled-down cap as hiding. Send the supervisor its path and your picks, and carry on.
- Strips of the new moves; the snow before and after. Pictures in `120-nod-button-weather/` in the notes folder.
- `scripts/test.sh macos` green once at the end (if a taller rain still changes `CompanionPerch.clearance`, say
  by how many points). The report COMMON asks for.
