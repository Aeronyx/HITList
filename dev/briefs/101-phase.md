# Brief 101: Phase, the ghost in the Mocha theme (session `phase`, effort xhigh)

George, 2026-11-11, after a morning with 0.9.3:

> Also, we need to replace some of the creatures that aren't cute, which includes Mocha, Rosé, and somewhat
> Graphite […] Some of these creatures could be a bit more fantastical:
>
> * The creature for Mocha is ugly; please remove and replace him with a sneaky, slightly transparent purple-y
>   ghost-like creature named Phase, with similar vibes to Shuppet in terms of design (pointy head, wavy body, larger
>   eyes and mischievous demeanor, etc.).
>
> And, some of them still don't sit on the "Add task" button quite right; they shouldn't look like they're floating
> above it or simply superimposed on top of it.

Mallow (Mocha's companion since last night) goes; **Phase** takes the theme. George's favourite of the eight is
Hush (Nord): look at Hush on the "+" at real size before you draw a pixel, and at why Mallow and Posy failed (a
small face on a blocky body, eyes like dots, nothing to love).

## Original, always (the supervisor's standing rule, `dev/SUPERVISOR.md` §7)
Nothing that is, or could be mistaken for, a character someone else owns ships in the app or sits in the
repository. George named an existing character to say what *kind* of thing he wants; take from his sentence the
traits he listed, which belong to ghosts in general, and nothing else: **a pointed head, a wavy hem, large eyes,
a sneaky, mischievous air, purple, slightly see-through.** Do not look up that character, do not reproduce its
silhouette, its head shape, its eye colours or markings, its palette or its name's style. Design Phase from the
Mocha palette outward and make choices of your own for every feature (what the point of the head does, what the
eyes look like, whether it has hands, how the hem moves). If a stranger could say "that is from the game", it is
wrong.

## What makes one of these cute (learned the hard way last night)
A head as large as the body or larger; eyes large, set wide and low, each with a glint; a small mouth or none;
round, soft shapes and one clear silhouette that reads at real size (a sprite is about 16 to 20 pixels tall: look
at it at 1x on a phone, not only at 8x); one idea of its own that makes someone smile. A ghost has a gift here:
it does not have to sit on the button at all, **it can be half inside it**: rising out of the "+" to the eyes,
sinking back, popping up further along, slipping through. That is the seat George asked for and the sneakiness in
one stroke; a ghost hovering above the button is exactly what he does not want.

## Do this first (within the first hour): three concepts, then ask
Draw three different Phases as stills (awake on the "+", asleep, one mischievous pose), at 8x and at real size on
the Mocha "+" and on the Mac's search field, with one line each on what makes it cute and what makes it its own.
Put the sheet in the shared notes folder (`101-phase/concepts.png`), message the supervisor (reply to the message
that brought you this brief) with your pick, and **carry on with your pick without waiting**; if the supervisor
answers with another pick or changes, switch.

## What Phase needs (the same as every companion; read these, they are the specification)
`dev/briefs/COMMON.md` (Round 20 block first); the format's header at the top of
`HITList/Support/Companions/CompanionCharacter.swift`; `dev/briefs/85-new-companions.md` (what a new character
file holds and how last night's were drawn and checked) and `91-weather-on-the-creature.md` (the weather is told
by the creature; nothing in the air); `dev/briefs/100-companions-alive.md` (the round's contract: an idle every 6
to 36 s, little loops, the seat and its check); last night's workshop (shared notes folder,
`84-companion-routines/workshop/`).
- Both places (the "+" on iPhone and iPad, the search field on the Mac), awake and asleep (22:00 to 07:00: a
  ghost asleep is its own joke; it still sleeps at night like the rest, the rule is the cast's).
- **Alive at the new pace**: awake at least six flickers and four little loops (`Routine(little: true)`), asleep
  at least two breaths; four or more long routines; a flourish; an answer to a tap. Mischief is the theme: a side
  glance, a grin, vanishing for a blink and coming back, peeking over the rim, sticking out a tongue.
- **The weather on a ghost** (take each idea that suits it, say why where one does not): rain falls through it,
  or it tries to catch one drop; snow can gather on the point of its head until it phases and the little heap
  drops; heat makes it droop like wax or hide inside the button to the eyes; thunder makes it jump.
- **See-through.** The format has seven solid inks. Add what Phase needs, additively and small, and document it in
  two lines of the format's header: either a character-wide opacity or a see-through ink (the hem fading out is
  the obvious use). It must look right over the glass "+" and over the Mac's field in every theme (Phase lives in
  Mocha, but `-companion phase` can show it anywhere), and `problems` must still pass for all eight characters.
- Every palette, `problems` empty, the seat check of brief 100 passed once it exists (until then: no background
  between Phase and the "+", measured on rendered pixels).

## Ownership
New `HITList/Support/Companions/Characters/Phase.swift`; `Mallow.swift` deleted; the Mocha line and Mallow's entry
in `CompanionCast.swift`; the see-through addition in `CompanionCharacter.swift` (the inks) and
`Views/Companions/CompanionSprite.swift` (the drawing); the lines that name Mallow in the companions' tests and a
test file of your own. Not yours: the schedule and the director (100: it is changing them now; your little loops
compile today and play once its engine commit is on master: the supervisor will message you; then
`git merge master`, build, and watch a whole minute), other characters, `ThemeCompanion.swift` (say in your report
where Phase should sit on Mocha's swatch in Settings: the supervisor sets it), Settings, `scripts/`, `dev/`,
`CHANGELOG.md`, `WhatsNew.swift`.

## How to work
Draw first with the workshop's scripts; build once, late; your own simulator (`HITList-101`), your own side store.
Look at every frame at real size. Debug arguments: `-companion phase`, `-companionSky rain|snow|heat|storm`,
`-companionSnowDepth 2`, `-companionPlay routine[:name]`, `-companionHour 23`.

## Done
The concept sheet; Phase at 8x and at real size in every still on both platforms; each idle, loop and routine as a
strip; a one-minute film strip awake and one asleep; the seat measured. How see-through was added. All three
suites green. The branch; one changelog line in plain words; where Phase sits on its swatch.
