# Briefs 87, 88, 89: the last three companions (sessions `graphite-companion`, `moss-companion`, `tokyo-companion`, effort max each)

One brief for three sessions; your prompt says which theme is yours. Each session draws **one** companion.

George, 2026-11-11, an hour into round 19:

> I've put you in Max mode to both continue on the roadmap after Round 19 completes and to hopefully create all the
> other creatures before I wake, as you have plenty of time. Don't rush anything, but please finish what you can by
> morning.

and, when he asked for one companion per theme: "keep with the theme of having them be familiar-but-not-quite-real
critters"; "these creatures are just for aesthetics and cute vibes".

Read `dev/briefs/COMMON.md` (Round 19 block first), `dev/briefs/ROUND-19.md`, `85-new-companions.md` (its "What
worked and what did not" is your art direction, word for word), `84-companion-routines.md` (what a companion does:
still, a flicker, a routine, the weather, the flourish) and `76-companions.md` ("The characters are ours": original
characters only; do not look for or work from other people's character art). Then the format, explained in thirty
lines at the top of `HITList/Support/Companions/CompanionCharacter.swift`, a finished character
(`Characters/Hush.swift`) and how they sit (`HITList/Views/Companions/CompanionPerch.swift`).

## The cast so far (yours must be unlike all of them)
Nod (Slate): a small person in a nightcap whose legs dangle. Quill (Midnight): a cat-like thing lying along the
edge, its tail in the accent. Hush (Nord): ears longer than itself. Posy (Rosé, being finished tonight): a round
piglet with wings far too small. Mallow (Mocha, being finished tonight): a fat soft toy in a knitted band. All
five at real size, in both places: `/Users/gtrammell/Desktop/HITList/build.noindex/round-19/reference/cast-so-far.png`
(Quill is in `round-18-all-four-in-place.png` beside it).

## Your theme and where to start
The seed is where to start, not what to deliver. Six silhouettes: four inside the seed's family, two that ignore
it; each also in ink at real size on your theme's "+" and on the Mac's search field, beside Nod and Hush. Star
the one that wins and say why. Three sessions draw at once without seeing each other, so the seeds differ on
purpose: stay in the neighbourhood of yours unless something much better turns up.
- **87 Graphite** (`graphite`: near-black, grey, a warm paper-white accent): *tall and thin*, an upright
  silhouette where the rest of the cast is squat. Graphite is pencil lead: something half-sketched, lanky, a bit
  awkward about its height.
- **88 Moss** (`moss`: dark forest green, a leaf-green accent): *low and wide*, close to what it sits on, carrying
  something that grows. The obvious first thought is a frog or a mossy rock: look for the second thought.
- **89 Tokyo Night** (`tokyo`: indigo night, a neon blue accent, a warm orange light): *a small thing with a
  light of its own* (the palette's warm ink and its glow), on a long tail or stalk that hangs over the edge the
  way Nod's legs do. A light gives it flickers nobody else has.

## The bar
George looks at these all day, loves Nod and Hush, called the last attempt for Rosé "a patterned wedge with a
nose" and had it redrawn. Face first, toward the viewer, readable at real size; big flat shapes; one odd,
memorable feature that is the whole character; charm over cleverness. Before you keep a design, say in three
words what a stranger would call it at real size: if the words are a shape or a pattern, it is not done. Familiar
but not quite real: a creature you feel you have seen and could not name. At most 20 by 20 pixels at 2 points a
pixel, four to six inks from the palette, one accent or warm detail. A short name of its own, unlike Nod, Quill,
Hush, Posy and Mallow.

## What it needs (one pass: the engine with routines is on master)
In both places (the Mac's field, the "+"): the resting pose; five gestures or more, two of them marked flickers
(a blink and the smallest thing only it can do); the reply to a tap; the flourish (its one party trick, 12 to 24
ticks, rest to rest); asleep, with a stir and a reply; rain and snow looks; **three routines or more** that could
belong to nobody else (four to nine moves, three to seven seconds, the in-between frames drawn); a rain routine
and a snow routine; a start at thunder (`sky: .storm`) and a clear-day routine only if you find ones you love.
`problems` must be empty for it (`CompanionSpriteTests` runs it on every character). Every frame on all eight
palettes (any companion can be forced on any theme with `-companion <id>`).
**Nothing floats**: the "+" is a capsule whose top edge curves down at both ends; at the line where your creature
meets it, or the field, there is no row of background between them and nothing sunk in, at 2x and 3x. Use
`Posture(inset:)` if it needs to sit further in.

## How to work tonight
- **Tools.** Brief 85's drawing workshop (frames as text, sheets at 8x and real size, mock-ups of the "+" at 3x
  and the field at 2x with the perch's geometry, a validator, a Swift generator) is snapshotted at
  `/Users/gtrammell/Desktop/HITList/build.noindex/round-19/workshop/`: copy it into your scratchpad (never edit it
  in place, never copy it into the repository), point `REPO` at your worktree, and draw with it.
- **The Mac is saturated** (eight sessions; swap is full). Draw first, with the scripts. Do not run a baseline
  suite. Build once, late: the Mac suite alone (`scripts/test.sh macos`; it holds every companion test), then one
  look in the real app at 3x in your own simulator (`HITList-NN`, booted only for that and shut down straight
  after) and at 2x in your own Debug Mac app (`HITLIST_STORE_SUFFIX=sNN`, quit after). The supervisor runs the
  three suites and the UI suite on the merged tree.
- Nobody answers questions tonight. Decide by this brief and write down what you decided.

## Ownership
A new `HITList/Support/Companions/Characters/<Name>.swift`; two lines in
`HITList/Support/Companions/CompanionCast.swift` (your character in `all`, your theme in `byTheme`: three
sessions add theirs at once and the supervisor resolves the merge, so change nothing else in that file); a new
`HITListTests/Companion<Name>Tests.swift`. Nothing else: not the engine or the views, not another character, not
Settings (the supervisor places your companion on its theme's swatch after the merge), not `dev/`, `CHANGELOG.md`
or `WhatsNew.swift`. If your character needs something the format cannot say, write it in the report.

## Done
The silhouette sheet with the pick and the reason; every frame at 8x and at real size; all eight palettes; in
both places by day, asleep, in rain and in snow, at 3x and 2x, beside Nod and Hush; each routine and the flourish
as a strip of frames with its timing; one routine recorded from the app if the machine allows. Its name, one line
on what it is, the three words a stranger would use. The Mac suite green; the branch name; one changelog line.
Where your drawing scripts are.
