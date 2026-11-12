# Brief 113: Glim improved, his tail out of the weather; Tuck's eyes at night (0.9.6)

Read `dev/briefs/COMMON.md` (the Round 22 block first), then this. **Concept sheet due 06:05, report due 07:20
Eastern.** Effort: xhigh.

## George's words (2026-11-12)
"In general, Glim needs an improvement." "Glim should hide his tali in the snow/rain" (his tail).

"Why do the snail's eyes become lines at night?" (Tuck.)

"The snow effects just looks like hats for many characters".

## What is there
- `Characters/Glim.swift` (Tokyo Night): a small round-eared creature that tends a light: the warm lantern at the
  end of what George calls his tail, hanging over the edge. In the pictures George saw (`round-22/george-saw/01-…`
  in the notes folder) his head reads as a dark block with square ears, the face is hard to find, and in snow he
  wears a flat white slab. Tests `CompanionGlimTests`; workshop and pictures `89-tokyo-companion/`,
  `105-cast-flavor/` in the notes folder.
- `Characters/Tuck.swift` (Moss): a snail beside its plant pot. Awake it has two eyes on stalks and a face; asleep
  the stalks are gone and two flat lines sit on its face. George's question is the finding: it reads as "its eyes
  turned into lines", not as a snail asleep. Tests `CompanionTuckTests`; workshop `88-moss-companion/`.

## What to make
1. **Glim, improved** (the same creature, the same seat and moves): a head with a shape (round ears with an inside,
   a clear face: eyes of his own with a light in each, a small nose or muzzle, cheeks), a body that reads as a
   body, the tail a clear line from his back to the light. His eyes must not be the round black eye with a glint
   (that is Button's from now on, COMMON). George's standard: cute beside Hush.
2. **His tail in rain and snow**: he takes it out of the weather. In the rain and snow stills the tail is curled
   in and the light is kept dry: held against his chest in both paws with the glow showing between them, or
   tucked under him with only a warm rim of light at his side; your choice by what reads. Moves for it: as the
   weather starts he reels the tail in and cups the light; now and then he peeks at it, blows on it, and tucks it
   back. In plain weather the tail hangs out as now.
3. **Tuck asleep**: answer George's question in the drawing. A snail asleep has drawn itself in: show two
   variants on the sheet (the stalks lowered and curled with closed, rounded lids that read as sleeping eyes; or
   the head drawn half into the shell with the stalks folded) and pick the one that reads as asleep at real size.
   No flat lines on the face. Its breathing carries over. Say in your report, in one sentence George can read, why
   the lines were there.
4. **Snow on both, to COMMON's recipe** (`s`, `b`, `c`): Glim's slab becomes a dusting on the tops of his ears and
   the crown between, his shoulders and back, none on the hidden light; Tuck's on the top of the shell following
   its curve, a little on the pot's rim and the plant's leaves, a fleck on each stalk's tip.

## Items, in this order
1. **A concept sheet by 06:05**: Glim, the 0.9.5 still and three improved ones, plus his rain and snow still with
   the tail hidden (two ways); Tuck asleep, two ways; at 1x, 2x and 3x on the "+" in their own themes and one each
   on the Mac's field. Send the supervisor the path and your picks with one line each, and carry on.
2. Glim's stills, then his idles and routines on the new drawing (his lantern-tending moves stay). One commit.
3. Glim's rain and snow with the tail hidden, and their moves. One commit.
4. Tuck asleep. One commit.
5. Snow on both.

## Ownership
`Characters/Glim.swift`, `Characters/Tuck.swift`, `HITListTests/CompanionGlimTests.swift`,
`HITListTests/CompanionTuckTests.swift`, their lines in `ThemeCompanion.seats`, their cases in the shared companion
tests. Not yours: the other creatures, the engine, the ink table.

## Done
- Sheets and strips in `113-glim-tuck/` in the notes folder: 0.9.5 beside now at 1x, 2x, 3x on the "+" and the
  Mac's field, awake, asleep, each weather, each snow depth, for both.
- `scripts/test.sh macos` green once at the end. The report COMMON asks for.
