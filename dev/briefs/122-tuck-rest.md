# Brief 122: Tuck at rest at night, and in a puddle in the rain (0.9.8)

Read `dev/briefs/COMMON.md` (the Round 24 block first: the water recipe is there), then this. **Sheet due 25
minutes after you start, report 85 minutes after you start.** Effort: xhigh.

## George's words (2026-11-12, on 0.9.7)
"Tuck: almost done, but his eyes/sprite don't make much sense during rain. He should be in a little puddle and/or
have a bit of water pool up in his pot. He also looks extremely depressed at night instead of like he's sleeping.
Can you make him look relaxed instead and perhaps with his eyes slightly bowed apart to show he's resting?"

Before that, still standing: (0.9.6) "Tuck's eyes should still droop down far at night, but they just looked
incorrect in the previous version. He also shouldn't smile while sleeping, that's creepy." (0.9.5) "Why do the
snail's eyes become lines at night?"

## What is there (`Characters/Tuck.swift`, Moss: a snail beside its pot and seedling; `view.py` shows any frame)
- Awake (`rest`): two eyes on upright stalks, a small smile, the pot with its seedling behind him. He is "almost
  done": this does not change.
- Asleep (`sleep`, round 23, the supervisor's own drawing): the stalks folded flat along his head, the shut eyes
  hanging at cheek level, no mouth, the body low. George: "extremely depressed". Everything limp and straight
  down is what reads as sad.
- Rain (`rain`): he stretches both stalks up tall, eyes wide, the seedling's leaves thrown open: alarmed, and not
  a drop of water in the picture.

## What to make
1. **Asleep, relaxed.** The supervisor is drawing this itself and will send you rows within about half an hour of
   your start; they are the starting point. Until they come, do item 2, and put up to three candidates of your own
   on the sheet. What "relaxed … eyes slightly bowed apart" means here: the two stalks lean gently away from each
   other, each in a soft outward bow, the shut eyes resting at their ends (one toward his nose, one back toward
   the pot), lids drawn as soft curves; the body rounded and settled, not flattened; still no mouth (or the
   smallest neutral one; never a smile); the eyes still clearly lower than by day ("droop down far"). Nothing
   hangs straight down, nothing is limp. Its breath (the eyes sway apart and back a pixel), the reply to a tap
   (one stalk lifts, its eye opens), and the asleep snow frames redrawn on the new pose.
2. **Rain: himself, in a puddle.** The rain still is his `rest` pose (stalks at their own height, his own eyes,
   content: he is a snail and this is his weather), with: **a little puddle he sits in** (water lapping along the
   front of his foot, a glint on it); **water pooled in his pot** (a blue line at the pot's brim with a glint, a
   drop running down its side or off the rim); a bead on a leaf of the seedling and one or two on his back and a
   stalk (COMMON's recipe). The drop that runs off falls from a leaf into the pot (the water there ripples) or
   from his eye stalk into the puddle. Retire the tall stretch as the still; keep it, if you like it, as one glad
   move in a rain routine (he reaches up to feel the rain, eyes half shut, and settles back), and the seedling may
   put out its leaves in the same routine. Asleep in the rain: a new still, the new asleep pose in the puddle, the
   pot brimming, a bead on him.
3. His snow is not touched but for the asleep pose's frames (item 1).

## The sheet (25 minutes)
The rain still (0.9.7 beside two candidates) and the asleep still (0.9.6's, 0.9.7's, the candidates), at 1x, 2x and
3x on the "+" in Moss and once on the Mac's field. Send the supervisor its path and your picks with one line each,
and carry on.

## Ownership
`Characters/Tuck.swift`, `HITListTests/CompanionTuckTests.swift`, Tuck's cases in the shared companion tests.
Nothing else: no awake plain, heat or snow frame changes.

## Done
- Before and after at 1x, 2x, 3x, strips of the breath, the tap and the drop, in `122-tuck-rest/` in the notes
  folder.
- `scripts/test.sh macos` green at the end. The report COMMON asks for, saying which idles no longer play in the
  rain (if any) and that no frame outside this brief changed.
