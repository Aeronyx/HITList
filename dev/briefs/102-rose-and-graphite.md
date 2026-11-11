# Brief 102: a mushroom for Rosé and a cuter creature for Graphite (session `rose-and-graphite`, effort xhigh)

George, 2026-11-11, after a morning with 0.9.3:

> Also, we need to replace some of the creatures that aren't cute, which includes Mocha, Rosé, and somewhat
> Graphite; the Moss snail is cute, but needs a glint in his eye or something to seem a bit less soulless. Some of
> these creatures could be a bit more fantastical:
>
> * Remove and replace Rosé's cow-bat thing with a cute mushroom creature.
>
> And, some of them still don't sit on the "Add task" button quite right; they shouldn't look like they're floating
> above it or simply superimposed on top of it.

and the night before: "Rosé is my favorite theme, so I definitely want it to have a good, adorable, silly lil'
creature." Posy (the piglet with wings, George's "cow-bat thing") goes. Graphite's Smudge (an owlet on long legs)
is "somewhat" not cute. Two characters, Rosé's first: it is the one George will look at every day.

George's favourite of the eight is Hush (Nord): look at Hush on the "+" at real size before you draw a pixel, and
at why Posy and Mallow failed (a small face on a blocky body, eyes like dots, nothing to love).

## What makes one of these cute (learned the hard way last night)
A head as large as the body or larger; eyes large, set wide and low, each with a glint; a small mouth or none;
round, soft shapes and one clear silhouette that reads at real size (a sprite is about 16 to 20 pixels tall: look
at it at 1x on a phone, not only at 8x); one idea of its own that makes someone smile. "Soulless" is what George
calls eyes without a glint.

## Original, always (`dev/SUPERVISOR.md` §7)
Nothing that is, or could be mistaken for, a character someone else owns. Mushroom people and small dragons,
ghosts and golems are everywhere in games; yours must be nobody's but ours. Do not look other characters up; make
a choice of your own for every feature, and if a stranger could say "that is from the game", it is wrong (for a
mushroom: no white cap with big coloured spots over a face and a vest, no walking brown cap with a frown).

## 1. Rosé: the mushroom
George's words: "a cute mushroom creature", "adorable, silly". Yours to design from the Rosé palette outward; some
directions, none of them an order: the cap is its hat, its umbrella and its bed (rain runs off the rim in one
drop; snow piles on the cap until it tips it off; in the heat it lifts the cap to fan itself or sits in its own
shade; asleep it pulls the cap down over its eyes); the face is on the stem, not the cap; short legs that dangle
over the front of the "+"; it can sway, bounce its cap, puff one spore when it sneezes (a single one, on itself:
nothing floats in the air), spin the cap like a parasol in its flourish. Name it (short, soft, one or two
syllables, nobody else's: "Bonnet" is the supervisor's suggestion, after the bonnet mushrooms; a better one
wins).

## 2. Graphite: cuter, and a little fantastical
Yours to design. The supervisor's suggestion, to beat or to take: **a gargoyle pup**, small and stone-grey, perched
on the edge of the "+" as its elders perch on a ledge (a seat that is the whole idea), big head, tiny wings,
stubby horns, a tail hanging over the front; a gargoyle is a rain spout, so in the rain it lets one drop fall from
its chin; snow piles between its wings; in the heat it lies flat on the cool stone; asleep it has "turned to
stone", curled and a shade paler. A redrawn Smudge (rounder, bigger eyes with a glint, shorter legs) is allowed if
it wins on cuteness at real size; something else of yours is allowed if it beats both. A new creature gets a new
name and id; Smudge's file goes if Smudge goes.

## Do this first (within the first hour): concepts, then ask
For each of the two, three different concepts as stills (awake on the "+", asleep, one pose that shows its idea),
at 8x and at real size on its theme's "+" and on the Mac's search field, with one line each on what makes it cute
and what makes it its own. Put both sheets in the shared notes folder (`102-rose-and-graphite/concepts-rose.png`,
`concepts-graphite.png`), message the supervisor (reply to the message that brought you this brief) with your
picks, and **carry on with your picks without waiting**; if the supervisor answers with other picks or changes,
switch.

## What each needs (the same as every companion; read these, they are the specification)
`dev/briefs/COMMON.md` (Round 20 block first); the format's header at the top of
`HITList/Support/Companions/CompanionCharacter.swift`; `dev/briefs/85-new-companions.md` (what a new character
file holds and how last night's were drawn and checked) and `91-weather-on-the-creature.md` (the weather is told
by the creature; nothing in the air); `dev/briefs/100-companions-alive.md` (the round's contract: an idle every 6
to 36 s, little loops, the seat and its check); last night's workshop (shared notes folder,
`84-companion-routines/workshop/`).
- Both places (the "+" on iPhone and iPad, the search field on the Mac), awake and asleep (22:00 to 07:00).
- **Alive at the new pace**: awake at least six flickers and four little loops (`Routine(little: true)`), asleep
  at least two breaths; four or more long routines; a flourish; an answer to a tap.
- **The weather on the creature**: rain (a drop off what it holds or wears, a shake-off), snow (two deeper stills
  and a routine that sends the pile off), heat (a still, a flicker, a routine), each in its own way.
- **The seat**: no background between the creature and the "+" anywhere along where they meet, at real size; its
  base follows the capsule's curve or is tucked behind the rim; legs or a tail may hang over the front. Brief
  100 is building the check every character must pass; until it exists, measure on rendered pixels.
- Every palette, `problems` empty.

## Ownership
New character files under `HITList/Support/Companions/Characters/`; `Posy.swift` deleted, and `Smudge.swift` if
Smudge goes; the Rosé and Graphite lines and those characters' entries in `CompanionCast.swift`; the lines that
name Posy and Smudge in the companions' tests and a test file per character. Not yours: the schedule and the
director (100: it is changing them now; your little loops compile today and play once its engine commit is on
master: the supervisor will message you; then `git merge master`, build, and watch a whole minute of each), the
inks and the sprite's drawing (101 is adding see-through ink), other characters, `ThemeCompanion.swift` (say in
your report where each should sit on its theme's swatch in Settings: the supervisor sets it), Settings,
`scripts/`, `dev/`, `CHANGELOG.md`, `WhatsNew.swift`.

## How to work
Draw first with the workshop's scripts; build once, late; your own simulator (`HITList-102`), your own side store.
Look at every frame at real size. Debug arguments: `-companion <id>`, `-companionSky rain|snow|heat|storm`,
`-companionSnowDepth 2`, `-companionPlay routine[:name]`, `-companionHour 23`.

## Done
The concept sheets; each character at 8x and at real size in every still on both platforms; each idle, loop and
routine as a strip; a one-minute film strip awake and one asleep, each; the seats measured. All three suites
green. The branch; changelog lines in plain words; the names you chose and why; where each sits on its swatch.
