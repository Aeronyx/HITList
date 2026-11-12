# Brief 119: Tuck asleep, drooping; Quill's derpy face back (0.9.7)

Read `dev/briefs/COMMON.md` (the Round 23 block first), then this. **Sheet due 25 minutes after you start, report
70 minutes after you start.** Effort: xhigh.

## George's words (2026-11-12, on 0.9.6)
"Tuck's eyes should still droop down far at night, but they just looked incorrect in the previous version. He also
shouldn't smile while sleeping, that's creepy. Try again."

"The new Quill is also a solid improvement, but I do kind of miss how the previous Quill looked like a derpy
cat-mouse combo and this Quill mostly just looks like a snarky cat, but please no major redesigns, only slight
changes if anything."

"Snow and rain need to be slightly more obvious on most of these creatures".

## What is there (look at `round-23/study.png` in the notes folder: the app, enlarged)
- **Tuck** (`Characters/Tuck.swift`, Moss: a snail beside its pot and seedling). Awake: two eyes on upright
  stalks, a smile. Asleep in 0.9.5: the stalks gone, two flat lines on its face ("eyes become lines": wrong).
  Asleep in 0.9.6 (brief 113): the stalks still upright with pale shut balls on top, and the smile kept: George
  finds the smile creepy, and wants the eyes to **droop far down**.
- **Quill** (`Characters/Quill.swift`, Midnight). 0.9.5: a pale cat-mouse with two tiny dark eyes far apart and
  low, a blank kind face. 0.9.6 (brief 112): a tabby: a dark M on the brow (at real size a frown), narrow bright
  eyes in the accent (snarky), a whisker pixel out to the side, inner ears, a pale muzzle, a ringed tail, stripes
  down the flank. `git diff f3da1e6 v0.9.6 -- HITList/Support/Companions/Characters/Quill.swift` shows it.

## What to make
1. **Tuck asleep: the stalks droop.** Both stalks bend over and hang down, as a flower wilts: out and down past
   the top of its head, the eyes hanging at their ends well below where they stand by day (level with its cheek,
   or lower, resting against its side or on the pot's rim), each eye shut under a lid. One stalk may hang lower
   than the other. **No smile**: no mouth at all, or one small flat pixel pair; try both. Its breathing carries
   over (the hanging eyes sway a pixel). A tap: one stalk lifts and its eye opens. Awake, nothing changes.
2. **Quill's face, slightly.** Keep 0.9.6's tabby body, tail and stripes. Give the face back its derp:
   - the eyes as in 0.9.5: small, dark, round, set wide and low, each with its light if 0.9.5 had one; not in the
     accent, not narrow;
   - no dark M: at most two faint short stripes high on the brow that cannot read as eyebrows (or none);
   - the whisker pixel that breaks the head's outline goes; the ears and muzzle as near 0.9.5's as the tabby
     allows.
   Seen at 1x beside 0.9.5 and 0.9.6: 0.9.5's face on 0.9.6's cat. That is all; every other frame carries the
   face by the script 112 used (`112-hush-quill/workshop`).
3. **Their weather, a little clearer**, each in character:
   - Tuck in rain: a snail is glad of it, and its seedling drinks. Make one thing read at a glance: the seedling's
     leaf held over its head like an umbrella with a drop running off its tip, or Tuck stretched up tall with a
     drop on each eye; your pick by what reads. In snow: drawn half down beside its pot, powder clear on the
     pot's rim, the leaves and its back.
   - Quill in rain already arches his tail over his head: keep it, add what makes it wet (ears back, a drop off
     the tail's tip). In snow: powder clear along his back and tail, his tail wrapped round his feet.
   Snow stays powder in the three inks (COMMON round 22's recipe), just a little more of it and never a cap.

## Items, in this order
1. **A sheet by 25 minutes**: Tuck asleep (0.9.5, 0.9.6, and three drooping candidates, with and without a
   mouth), Quill's face (0.9.5, 0.9.6, two candidates), each at 1x, 2x and 3x on the "+" in its theme and one on
   the Mac's field. Send the supervisor its path and your picks with one line each, and carry on.
2. Tuck asleep (the still, the breath, the tap, asleep in rain and snow). One commit.
3. Quill's face on every frame. One commit.
4. The weather stills and their moves. One commit each creature.

## Ownership
`Characters/Tuck.swift`, `Characters/Quill.swift`, `HITListTests/CompanionTuckTests.swift`, their lines in
`ThemeCompanion.seats`, their cases in the shared companion tests. Nothing else.

## Done
- Sheets and strips in `119-tuck-quill/` in the notes folder: v0.9.6 beside now at 1x, 2x, 3x.
- `scripts/test.sh macos` green once at the end. The report COMMON asks for.
