# Brief 117: Gargle awake as the night sprite George adores (0.9.7)

Read `dev/briefs/COMMON.md` (the Round 23 block first), then this. **Sheet due 30 minutes after you start, report
75 minutes after you start.** Effort: xhigh.

## George's words (2026-11-12, on 0.9.6)
"I do not like the new Gargle; your new direction with him isn't awful, but he's a tad too big and not cute enough.
I still adore the nighttime sprite, but that's the only one I like."

"Snow and rain need to be slightly more obvious on most of these creatures (… Gargle might hide under a wing …)".

Before that (on 0.9.5): "Gargle looks like he's throwing up, but I don't mind all of his animations, his nighttime
sprite is quite cute, I like that he's side-on for some postures. Perhaps turn him into a bit more of a dragon
with a different eye and mouth style." And on 0.9.4: "looks a bit lazy visually/like a grey blob".

## What is there
`Characters/Gargle.swift` on master (0.9.6, brief 111). Look at `round-23/study.png` in the notes folder (the app,
enlarged):
- **The night sprite** (frame `sleep` and the asleep mode): pure profile, snout to the left, the eye a closed
  line, two small pale horns, the folded wing up behind him like a cape, a compact stone body, the tail's spade
  behind the bar. Simple, small, one read. This is the Gargle George loves.
- **Awake in 0.9.6**: a larger three-quarter head with a near eye and a narrower far eye, a muzzle, a fang, a
  brow. Too big, too busy, not cute.
The supervisor's own mistake, twice: asking for a face turned toward the viewer because "a face must look at you".
George likes him side-on.

## What to make
**Awake, he is the night sprite with his eye open.** Start from the `sleep` frame's rows and change as little as
makes him awake:
- The same profile, the same size or a touch smaller (the night sprite's own height is the ceiling: "a tad too
  big"), the same horns, wing, body and tail. Head up a pixel or two from the sleeping pose at most.
- **One eye, open, and it carries him**: round and friendly, 3 × 3 or so, with a light in it and a warm iris if it
  reads (the theme's warm ink, as 0.9.6 used), looking a little toward the viewer rather than dead ahead. Try a
  plain dark eye with a light as well. Cute beside Hush at 1x is the test; "soulless" is George's word for an eye
  with no light.
- **The mouth**: closed, a short line with the corner up, or nothing. No fang unless it helps; nothing that can
  read as something leaving his mouth.
- **Dragon, lightly** ("isn't awful"): the short snout and the little horns he already has, perhaps one nostril
  pixel; smoke stays in the moves. No more than the night sprite carries.
- **The night sprite itself does not change by one pixel**: a test pins the asleep stills to digests of v0.9.6's.

## Items, in this order
1. **A sheet by the half hour**: v0.9.6's `sleep`, v0.9.6's awake `rest`, and three awake candidates built on the
   sleep frame (eye and mouth variants), each at 1x, 2x and 3x on the "+" in Graphite with Hush beside it, and one
   on the Mac's field. Send the supervisor its path and your pick with one line of why, and carry on.
2. `rest` in both postures and the blink (the blink is nearly the night sprite: good).
3. The idles and routines on the new head: a glance, an ear or horn flick, the wing ruffled, the spade wagging
   behind the bar, a yawn, the smoke puff and the ember hiccup (kept, small), the statue game (he is already in
   profile: he freezes, eye shut, and peeks). Drop what needs the three-quarter head. Fewer, all good, beats many.
4. **Rain: he hides under his wing.** The still: the wing lifted and held over his head like a roof, his eye
   looking up or out from under it, a drop running off the wing's tip. Now and then he peeks out and ducks back.
   Thunder: he ducks right under.
5. **Snow** (COMMON round 22's recipe, a little clearer than 0.9.6's): powder along his back, the wing's upper
   edge, the horns' bases and his snout; deeper, he tucks his snout under the wing. The shake-off stays his.
6. His swatch in Settings (`.peeking`: it needs his eye row; check the grid's height does not grow), the Duo's
   island seat, the tests.

## Ownership
`Characters/Gargle.swift`, `HITListTests/CompanionGargleTests.swift`, Gargle's line in `ThemeCompanion.seats`,
Gargle's cases in the shared companion tests. Nothing else.

## Done
- Sheets and strips in `117-gargle-pup/` in the notes folder: v0.9.6 beside now at 1x, 2x, 3x, awake, asleep
  (identical), rain, each snow depth.
- `scripts/test.sh macos` green once at the end. The report COMMON asks for.
