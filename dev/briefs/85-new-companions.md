# Brief 85: Rosé's companion, again, and the plushy (session `new-companions`, effort max)

George, 2026-11-11, on 0.9.2:

> Pip does kind of seem like a patterned wedge with a nose; maybe scrap or retry that one. Rosé is my favorite
> theme, so I definitely want it to have a good, adorable, silly lil' creature. Hush is awesome as you confirmed.
>
> What happened to the creature in my attached screenshot? I loved him! Maybe he was just an interim design before
> Hush, but I still think he's adorable. He looks like a plushy. Perhaps redo his colors and change his design
> slightly and use him as the base for another fatter round character.

Read `dev/briefs/COMMON.md` (Round 19 block first), `dev/briefs/ROUND-19.md`, `79-companion-cast.md` and
`76-companions.md` (the art direction and "The characters are ours" bind you: original characters only, never
anyone else's, and do not look for or work from other people's character art), then the characters as data:
`HITList/Support/Companions/CompanionCharacter.swift`, `Characters/Nod.swift`, `Hush.swift`, `Pip.swift`, and how
they sit: `HITList/Views/Companions/CompanionPerch.swift`.

You draw two companions: **Rosé's**, replacing Pip, and **the plushy**, for a theme of its own. Brief 84 is
changing the engine beside you (idle routines, weather that moves); you draw in today's format, and the
supervisor sends you a second pass when 84 is merged.

## What worked and what did not (from George's reactions)
- **Nod** ("I love the guy who hangs out over the search bar") and **Hush** ("awesome"): a light face turned to
  the viewer, two eyes you can read at real size, a body of two or three flat tones, one odd feature that is the
  whole character (legs that dangle; ears longer than itself), a silhouette you could cut from black paper.
- **Pip** ("a patterned wedge with a nose"): seen from the side, a body made of texture, a face three pixels
  wide. At real size the pattern was noise and the creature was a shape. Pattern is not character.
- **The plushy** ("adorable… looks like a plushy"): round, flat-faced, two stubby ears, a band across the middle,
  tiny feet. Soft and simple.
So: face first, toward the viewer; big flat shapes; one odd, memorable feature; charm over cleverness. Before you
keep a design, say in three words what a stranger would call it at real size. If the words are a shape or a
pattern ("a wedge", "a blob with a nose"), it is not done.

## Rosé's companion
Rosé is George's favourite theme, so this one meets the highest bar: **adorable and a little silly**, something
that makes a person smile when they notice it by the "+". Familiar but not quite real, as the others are. Rosé's
palette is a dusky plum with a rose-pink accent: one accent detail, no more. Eight silhouettes this time (not
six), each also drawn in ink at real size sitting on Rosé's "+" and on the Mac's search field, beside Nod and
Hush at the same size for comparison; star your pick and say why, and say what is silly about it. Then stop and
look again an hour of work later: if it does not hold up beside Hush, pick again. Pip goes: delete `Pip.swift`
and every mention; Rosé maps to the new one.

## The plushy
An interim sketch from round 18 that never shipped (ours; George's crop of it is at
`/Users/gtrammell/Desktop/HITList/build.noindex/round-19/reference/plushy-sketch-8x.png`, outside the repository:
read it, do not copy the file into the repository). As pixels, in Nord's inks (`.` clear, `d` dark, `m` mid,
`L` light, `a` accent, `k` the eyes):

```
.....d........d.....
.....dd......dd.....
.....dmd....dmd.....
.....dmmmmmmmmd.....
....dmLLLLLLLLmd....
....dmLkLLLLkLmd....
....dmLLLLaLLLLmd...
...dLLLLLLLLLLLLd...
..dLmLmLmLmLmLmLLd..
..dLLLLLLLLLLLLLL...
...dmmmmmmmmmmmmd...
...dmmmmmmmmmmmmd...
...dmmmmmmmmmmmmd...
....dmmmmmmmmmmd....
.....dddddddddd.....
......LL....LL......
```

(The transcription is the supervisor's and may be a pixel off; the picture is the source.) George's words are the
brief: keep what he loved (the plush look: stubby ears, the flat pale face, the band, the tiny feet), make it
**fatter and rounder**, **change the design slightly** so it is its own creature and not Hush's cousin, and
**redo its colours** (which ink goes where; the band is the obvious place for the theme's accent or its warm ink).
It reads as a soft toy of an animal nobody can quite name. Give it a theme of its own from Graphite, Moss, Tokyo
Night and Mocha: choose the one whose palette and name it answers best and say why. Four silhouette variations on
the sketch (how fat, which ears, what the band is), your pick starred.

## For each of the two (today's format, as `Hush.swift` is written)
The resting pose in both places (the Mac's field, the "+"), four small gestures or more (two of them the
smallest kind: a blink, one small movement), the reply to a tap, the flourish (its one party trick, as particular
to it as Nod's lantern and Hush's sneeze are to them), asleep and a stir, rain, snow. At most 20 by 20 pixels at
2 points a pixel, four to six inks from the palette, one accent or warm detail. **Nothing floats**: at the line
where it meets the "+" (a capsule: its top edge curves down at both ends) or the field, no row of background
between them at 2x or 3x, in your simulator and on the Debug Mac app. Every frame on all eight palettes (a
companion can be forced on any theme with `-companion <id>`).

## The second pass (the supervisor sends it when briefs 84 and 86 are merged)
Merge master into your branch, then: three idle routines or more and the weather routines for each of your two,
in brief 84's format (explained at the top of `CompanionCharacter.swift` by then), and how each sits on its
theme's swatch in Settings (brief 86's small sprites: a table with one entry per character). End your first pass
with the report below and wait; do not start the second pass from guesses.

## Ownership
New `HITList/Support/Companions/Characters/<Name>.swift` for each; `Characters/Pip.swift` (delete);
`HITList/Support/Companions/CompanionCast.swift` (the list and the theme map); the lines that name Pip in
`HITListTests/Companion*Tests.swift` and `HITListUITests/CompanionsUITests.swift` (those lines only: brief 84 owns
the rest of those files); a new `HITListTests/CompanionNewCastTests.swift`.
Not yours: the engine and the views (`CompanionCharacter`, `CompanionClock`, `CompanionDirector`,
`CompanionSchedule`, `Views/Companions/*`), `Nod.swift`, `Quill.swift`, `Hush.swift` (84), `CompanionSkySource.swift`
(the supervisor's), every Settings view (86), `Services/Weather/*` (83), `dev/ROADMAP.md`, `CHANGELOG.md`,
`WhatsNew.swift`. If a character needs something the format cannot say, write it in the report: do not change the
engine.

## Done (first pass)
For each: the silhouette sheet with the pick and the reason; every frame at 8x and at real size; all eight
palettes; in both places at real size by day, asleep, in rain and in snow, iPhone (3x) and Mac (2x), with Nod and
Hush beside it at the same scale; the flourish as a strip recorded from the app. The name of each, its theme and
why, one line on what it is, and the three words a stranger would use. All three suites green, the companions' UI
tests on a fresh simulator. Keep your drawing scripts in your scratchpad and say where.
