# Brief 134: Phase looks down and to the left in the rain (session `phase-rain`, effort xhigh)

George, 2026-11-14, on 0.9.9:

> Have Phase looking down left for rain instead, he looks weird looking up constantly.

Round 25 (brief 129) put his black eyes back with a white pupil: down and to the right by day, toward the snow
pile in deep snow, and up and to the left in the rain (George then: "looking away/up left during rain is still
good"). Having lived with it, the upward look held for a whole rainy day is what reads wrong.

Read `dev/briefs/COMMON.md` (the Round 27 block first, then Round 25's and 24's creature rules),
`dev/briefs/ROUND-27.md`, `dev/briefs/129-phase-eyes.md`, the workshop that wrote his eyes
(`129-phase-eyes/workshop` in the notes folder: `mine.py` holds the rain pupil's corner in one line, `eyes.py`,
`write.py`, `v099-Phase.swift`), then `Characters/Phase.swift` and `HITListTests/CompanionPhaseTests.swift`.

## What changes
1. **In the rain his pupils sit at the lower left of each eye**, in every awake frame the rain shows: `rain`,
   `rainFall0`…`3`, `rainDrop0`…`4`, `rainShiver`, and any storm frame that is a still of the same look. He is
   watching the water gather at his feet, not the sky. Do it by script from master's file, as 129 did, so nothing
   else in a frame moves; the report lists the frames and the pixels that changed in each (two to four a frame).
2. **The moves in the rain end where the still is.** The `watch` routine and the storm's `thunder`, `stormDart`,
   `stormPeek` may still glance elsewhere for a tick (a sudden look up at thunder is his character), but every
   hold and every last frame is the down-left look. If a routine was built around looking up (watching the rain
   fall), turn it into watching the drop land: say what you did.
3. **Nothing else.** His body, its see-through thinning, his fade, the day look (down and to the right), the snow
   look, asleep, his water. Every frame name stays (132 builds a cheer from his frames by name). No engine change.
4. **Tests**: pin the rain pupil's corner (the test that pins up-left today becomes down-left), every open eye
   still several pixels with one white pupil, no white eye anywhere.

## The sheet (due 20:45 Eastern)
Before and after at 1x, 2x and 3x on the "+" in Mocha and once on the Mac's field: the rain still, one drip strip,
the `watch` routine as a strip. One line of why if you chose anything. Send the supervisor its path and carry on;
it goes to George at once.

## Ownership
`HITList/Support/Companions/Characters/Phase.swift`, `HITListTests/CompanionPhaseTests.swift`, Phase's cases in
`CompanionLightTests` and the other shared companion tests. Nothing else.

## Done (report due 21:15 Eastern)
Draw first and build once: no simulator; `scripts/test.sh macos` green; one look in a Debug Mac app of your own
(`HITLIST_STORE_SUFFIX=s134`, `-companion phase`, rain forced) if the clock allows. The report COMMON asks for.
