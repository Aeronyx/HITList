# Brief 130: Nod's canopy floats again; Tuck asleep has a mouth and droops a little more (0.9.9)

Read `dev/briefs/COMMON.md` (the Round 25 block first), then this. **Sheet due 20 minutes after you start; report
60 minutes after you start.** Effort: xhigh.

## George's words (2026-11-12, on 0.9.8)
"Nod's umbrella was supposed to be a wooden stick he holds with his right hand and... hm, nevermind, just restore
his 0.9.6 canopy. It'll just be a little floating canopy over his head."

"Why does Tuck now have no mouth when sleeping? I just said the smile was weird, not to remove the mouth entirely!
Please put back a little line mouth to show when he's resting. His eyes can also droop a bit more now that they're
bowing out just a bit; I just want him to look at peace."

Still standing from before: (0.9.6) "He also shouldn't smile while sleeping, that's creepy." (0.9.8, of the other
creatures) "all looking good along with the new weather effects".

## What is there
- **Nod** (`Characters/Nod.swift`, Slate). 0.9.6's `rain` (`git show v0.9.6:…/Nod.swift`): a small striped canopy
  with a peak over his cap, rows 0 to 3, nothing holding it. 0.9.8 (brief 123) kept that canopy pixel for pixel,
  added blue beads on it, a drop off its rim, two small pools beside his seat, **and a handle**: a shaft of `m` at
  column 1, rows 4 to 7, with his hand `l` at column 1, row 8; asleep in the rain the shaft is tucked in his arm.
  The no-handle build is one switch in `123-quill-nod/workshop/nbuild.py` in the notes folder.
- **Tuck** (`Characters/Tuck.swift`, Moss). Asleep since 0.9.8 (brief 122, the supervisor's rows): his daytime
  head, the two shut eyes on short stalks leaning apart, no mouth:
  ```
  ..............a.....
  .mm.....mm...aa.....
  mllm...mllm..aa.....
  mddm...mddm..a......
  .dd.....dd...a......
  ...l...l.dddddddddd.
  ..dlllllddmmmmmmmmd.
  .dllllllldddddddddd.
  dllllllllldmmmmmmd..
  dllllllllldmmmmmmd..
  dlllllllll.dmmmmd...
  dlllllllll.dddddd...
  ```
  By day his mouth is a smile: `dlldllldll` over `dllldddlll` (corners up at columns 3 and 7, the line at 4 to 6).

## What to make
1. **Nod: the handle goes, everywhere.** No shaft and no hand at the canopy in any frame: the rain still, every
   frame drawn whole for the rain, the gestures over it, asleep in the rain and its drips. His arm is where it is
   in `rest`. The canopy is 0.9.6's, floating over his cap, with 0.9.8's beads, its drop and the two pools (the
   water is not what he objected to; say so in your report as a choice he may reverse, and keep the dry 0.9.6
   still one switch away in the workshop). A move that only made sense with a handle goes or becomes the canopy's
   own (it may bob a pixel, as a thing that floats does; a drop may run round its rim): few, and good. With the
   handle gone, check which idles play in the rain again (0.9.8 skipped five) and say. A test pins the canopy's
   rows 0 to 3 to `v0.9.6`'s shape (water inks aside) and that nothing stands between the canopy and his hand.
2. **Tuck asleep: a little line mouth, at peace.** The supervisor is drawing this and will send rows within about
   fifteen minutes of your start; they are the starting point. Until then do Nod, and put two candidates of your
   own on the sheet. What he asks for: a short flat line where the smile's line is by day (two or three pixels of
   `d`, no corners turned up: resting, never smiling, never a frown); the eyes drooping a little more than now
   (the stalks bowing out and down, the shut eyes resting lower, toward the level of his brow; not hanging
   straight down at his cheeks, which is what read as "extremely depressed" in 0.9.7). Then carry it to every
   asleep frame: `sleep`, `sleepBreath`, `sleepLeaf`, the peeks, the three asleep snows, asleep in the rain.

## The sheet (20 minutes)
Nod's rain still and asleep-in-rain still, 0.9.6, 0.9.8 and yours; Tuck asleep, 0.9.7, 0.9.8 and the candidates;
each at 1x, 2x and 3x on the "+" in its theme and once on the Mac's field. Send the path and your picks with one
line each, and carry on.

## Ownership
`Characters/Nod.swift`, `Characters/Tuck.swift`, `HITListTests/CompanionTuckTests.swift`, Nod's and Tuck's cases in
the shared companion tests. No awake plain, heat or snow frame of either changes; nothing of Tuck's by day. Not
`ThemeCompanion.swift` (131 moves Tuck's seat).

## Done
- Before and after at 1x, 2x and 3x, a strip of Tuck's breath and of Nod's drop, in `130-nod-tuck/` in the notes
  folder.
- `scripts/test.sh macos` green at the end. The report COMMON asks for, with the counts of frames changed, each
  creature, and a line that nothing else did.
