# Brief 129: Phase's black eyes back, and a worried look at the snow (0.9.9)

Read `dev/briefs/COMMON.md` (the Round 25 block first), then this. **Sheet due 20 minutes after you start; report
70 minutes after you start.** Effort: xhigh.

## George's words (2026-11-12, on 0.9.8)
"Please put Phase's black eyes back! The new white eyes you added for him ruin his entire vibe. Please make them
majority black with a white pupil again and have him once again looking down to the right by default/day and also
have him looking at the snow pile with mild concern instead of away from it during deep snow (looking away/up left
during rain is still good). The other opacity and design changes you made for him are great."

## What is there (`Characters/Phase.swift`, Mocha; 164 frames)
- **0.9.7's eyes** (the ones he wants): `git show 89e7572:HITList/Support/Companions/Characters/Phase.swift`. Each
  eye is a block of `k` two wide and two or three tall with one `l` pupil at its lower right:
  ```
  .......aakkaaakkaa..
  .......aakkaaakkaa..
  ......aaaklaaakla...
  ```
  By day he looks down and to the right. In deep snow 0.9.7's pupils were at the same corner, away from the snow.
- **0.9.8's** (round 24, brief 121): the same blocks in `l` with a `k` pupil, lit and glowing (`glow:` in his
  `CompanionCharacter(` call, `Frame(light:)`), and a move in which his body fades until his eyes hang alone. The
  body is see-through from crown to hem, thins and fills in his moves, the tail ends in a wisp, one mound of snow:
  all of that George calls great and none of it changes.
- The snow's one mound lies under his left side (columns 3 to 11); his eyes are at columns 9 to 10 and 14 to 15.

## What to make
1. **The eyes are 0.9.7's on every frame**: majority black, one white pupil. Where a frame exists at `89e7572`,
   its eye pixels come from there, pixel for pixel; the frames round 24 added get eyes in the same hand. By day
   and by default the pupils are low and to the right, as in 0.9.7's `rest`. Black stays black: the eyes are solid
   on the see-through body (that contrast is the look), and nothing lightens them.
2. **No white eyes anywhere, in any move.** The glow on his eyes goes, or stays only if it can sit on the pupil
   alone without greying the black at 1x (show both on the sheet at 1x and say which you chose; the engine is not
   yours to change, so if the pupil alone cannot glow, it does not). The move that fades his body to his eyes
   alone: keep it only if what is left reads well at 1x with black eyes (two pupils hanging in the dark, the body
   filling in round them); otherwise it ends at a faint body, and you say so. Glim's glow is not touched.
3. **In snow he looks at the pile, a little worried.** At `snowDeep1` and `snowDeep2` (and the frames drawn whole
   on them): the pupils turn down toward the mound (low and to the left), and "mild concern" is two or three
   pixels, not a new face: for example the top outer corner of each eye rounded off, or one pixel of the body's
   shade over each eye as a brow tipped up at the middle. Three candidates on the sheet beside 0.9.7's and 0.9.8's
   deep snow. In light snow (`snow`) he glances down at it without the worry. Asleep is not touched.
4. **Rain stays as it looks**: away and up to the left, now in black with the white pupil at the upper left.
5. The blink, the glances, the sly looks, the wide eyes, the reply to a tap: all in black again, and each still
   plays where it played (say which do not).

## The sheet (20 minutes)
`rest`, `rain`, `snow`, `snowDeep2` and the fade's last frame: 0.9.7, 0.9.8 and yours, at 1x, 2x and 3x on the "+"
in Mocha and once on the Mac's field; the three "concern" candidates. The supervisor's renderer does not draw the
see-through body or the glow: for the truth build once and look in a Debug Mac app of your own. Send the sheet's
path and your picks with one line each, and carry on.

## Ownership
`Characters/Phase.swift`, `HITListTests/CompanionPhaseTests.swift`, Phase's cases in `CompanionLightTests` and the
other shared companion tests, `HITListUITests/CompanionPhaseUITests.swift` if it names the eyes. Not the engine,
not Glim, not `ThemeCompanion.swift`.

## Done
- Before and after at 1x, 2x and 3x by day, in rain, in each snow, asleep, and a strip of the fade, in
  `129-phase-eyes/` in the notes folder; one picture from the real app (Debug Mac, `HITLIST_STORE_SUFFIX=s129`,
  `-companion phase -pref.theme mocha`) by day and in deep snow.
- `scripts/test.sh macos` green at the end. The report COMMON asks for, with the count of frames whose eyes
  changed and a line that nothing but eyes (and the glow's setting) did.
