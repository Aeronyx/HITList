# Brief 116: Glim as he was, with Hush's kind of small touches (0.9.7)

Read `dev/briefs/COMMON.md` (the Round 23 block first), then this. **Sheet due 30 minutes after you start, report
75 minutes after you start.** Effort: xhigh.

## George's words (2026-11-12, on 0.9.6)
"Oh no, what happened to Glim? Please scrap him entirely and either use 0.9.5 Glim or try to upgrade him again but
with much more subtle changes. The new sprite is so much worse."

"Hush is actually the perfect example of a good rework; you kept his vibe without changing much, just slight
improvements to coloration and design. Keep the new Hush, and if you can, use that same direction to slightly
upgrade Glim from 0.9.5 (a tiny bit more color shading and such, but largely imperceptible changes unless you're
looking closely)."

Earlier (on 0.9.5, still standing): "Glim should hide his tail in the snow/rain." And of the weather now: "Snow
and rain need to be slightly more obvious on most of these creatures".

## What is there
- **0.9.5's Glim**, the one he wants: `git show f3da1e6:HITList/Support/Companions/Characters/Glim.swift` (a copy:
  `113-glim-tuck/Glim-0.9.5.swift` in the notes folder), its tests `git show f3da1e6:HITListTests/CompanionGlimTests.swift`.
  A small mouse: a dark hood of fur with two round ears (pale inside), a pale round face with two small dark eyes
  and a small mouth, a pale body, a ringed tail out to a warm lantern that hangs over the edge. Its round 21 idles
  (he sniffs, steadies and swings the lantern, cups the flame, lifts it to peer).
- **0.9.6's Glim** (master): redrawn pale with big ears, lit eyes and cheeks. Scrap it: no frame of it stays.
- **What 0.9.6 did to Hush**, the model: `git diff f3da1e6 v0.9.6 -- HITList/Support/Companions/Characters/Hush.swift`
  and `112-hush-quill/sheet/hush-plus.png`: the inside of each ear in a second tone, a small peak of fur inside the
  outline, a soft lower lid, a small belly. The eyes, the seat row, the eye row and the outline did not change. At
  1x it is the same Hush.

## Items, in this order, one commit each
1. **0.9.5's Glim back, whole**: every frame, mode, gesture and routine of `f3da1e6`'s file, brought to today's
   format where the format moved (snow inks, the tests). A test pins his plain stills (awake and asleep, both
   postures) to digests of `f3da1e6`'s rows, as Button's are pinned to `v0.9.4`.
2. **Hush's kind of touches**, on that drawing, and nothing more: the outline, the eyes, the face's shape, the
   ears' shape, the seat and every pose stay pixel for pixel. Inside the outline only, a handful of pixels: a
   second tone where one tone is flat (the hood's lower edge or under the chin, the ears' inside, a paler belly or
   chest, the tail's far rings, a rim of glow on the lantern). **Seen at 1x beside 0.9.5's, a stranger says "the
   same"; at 3x he finds the differences.** If a touch can be seen at 1x, it is too much: take it out. Carried
   onto every frame by a script, as 112 did. Update the digests' test to the new stills and keep one that counts
   the changed pixels per still (a ceiling you set after looking: a dozen or so).
3. **His light out of the weather**, on the 0.9.5 body. 0.9.5's rain still already holds the lantern at his side;
   make it read at a glance and hide the tail: the tail curled in against him, the lantern held to his chest in
   both paws with the glow showing between them, his head bent over it a little. In snow the same, and he **warms
   his paws at it**: now and then he lifts it, blows, and tucks it back. Nothing else about him changes in the
   weather. Show the rain and snow stills beside 0.9.5's and 0.9.6's.
4. **Snow as powder** (COMMON round 22's recipe, inks `s`, `b`, `c`) on the 0.9.5 body, a little clearer than
   0.9.6's: on the hood's top between and on the ears, his shoulders, none on the light. 0.9.5's slab is gone.

## Ownership
`Characters/Glim.swift`, `HITListTests/CompanionGlimTests.swift`, Glim's line in `ThemeCompanion.seats`, Glim's
cases in the shared companion tests. Nothing else.

## Done
- A sheet by the half hour, at 1x, 2x and 3x on the "+" (Tokyo Night) and one on the Mac's field: 0.9.5, your
  touched-up still (two or three strengths of touch), awake and asleep; rain and snow. Send the supervisor its
  path and your pick with one line of why, and carry on.
- `scripts/test.sh macos` green once at the end. The report COMMON asks for, pictures in `116-glim-subtle/`.
