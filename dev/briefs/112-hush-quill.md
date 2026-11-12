# Brief 112: Hush and Quill, a little more drawn (0.9.6)

Read `dev/briefs/COMMON.md` (the Round 22 block first), then this. **Before-and-after sheet due 06:05, report due
07:20 Eastern.** Effort: xhigh.

## George's words (2026-11-12)
"Hush (and Quill to some extent) is starting to look a bit basic now that the other characters are so well done.
Give them minor tweaks and updates to improve their designs while maintaining their styles/postures."

"The snow effects just looks like hats for many characters (especially Quill)."

## What is there
`Characters/Hush.swift` (Nord: one soft pale shape, long ears hanging down over the front, large eyes; George's
standard for cute since round 20, and one of the two that still hang down) and `Characters/Quill.swift` (Midnight:
a cat, its tail's tip inked in the accent, lying along the Mac's field and sitting on the "+"). Round 21 gave each
idles of its own (Hush listens, Quill is a cat). Their tests are in the shared companion tests; workshops
`105-cast-flavor/workshop` (`quill_new.py`, `cf.py`), `84-companion-routines/workshop`, `85-new-companions/` in the
notes folder.

## What to make
The same two creatures, in the same places and postures, with the same moves, **drawn with more care**: what the
newer ones have and these lack is a second tone, a few details that reward a close look, and a silhouette with a
little more shape. Nothing George would call a different character. Try, and keep only what improves it at real
size:
- **Hush**: the ears given an inside (a darker or accent-tinted inner ear, a fold where they hang, tips that curl);
  a tuft between the ears; a soft patch on the chest or belly; paws that show; the eyes a touch richer (a larger
  light, a lower lid when it smiles); a hint of cheek. Hush's eyes are its own already: keep their character.
- **Quill**: a cat's markings (a few tabby bars on the back or the tail, a darker saddle, a pale bib or socks);
  inner ears; cheek fluff and whisker pixels; a nose; the tail with more shape toward the inked tip. Lying along
  the field it should read at once as a cat lying down.
- Stay inside each creature's size and seat: a change that moves the seat row, the eye row or the outline over the
  host means the seat tests and the swatch need checking; prefer changes inside the outline.

## Items, in this order
1. **A before-and-after sheet by 06:05**: for each of the two, the 0.9.5 still and two or three improved ones, at
   1x, 2x and 3x on the "+" and on the Mac's field in its own theme. Send the supervisor the path and your pick for
   each with one line of why, and carry on with your picks.
2. Hush: the stills (awake, asleep, both postures, each weather), then every idle and routine carried onto the new
   drawing. One commit.
3. Quill: the same. One commit.
4. **Snow on both, to COMMON's recipe** (`s`, `b`, `c`). Quill's is the one George named: today a white cap sits on
   his head like a hat. A cat in the snow has powder along its back and the top of its tail, a little on each ear
   tip and the crown between them, a fleck on the nose. Hush's hood of white becomes a dusting along the top of the
   head and down the outside of each ear, deeper where the ears leave the head.

## Ownership
`Characters/Hush.swift`, `Characters/Quill.swift`, their lines in `ThemeCompanion.seats`, their cases in the shared
companion tests (a test file of your own for anything new: `CompanionHushQuillTests.swift`). Not yours: the other
creatures, the engine, the ink table.

## Done
- Sheets and strips in `112-hush-quill/` in the notes folder: 0.9.5 beside now at 1x, 2x, 3x on the "+" and the
  Mac's field, awake, asleep, each weather, each snow depth, for both.
- `scripts/test.sh macos` green once at the end. The report COMMON asks for.
