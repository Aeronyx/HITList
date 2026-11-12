# Brief 103: Button stands on the bar, small and sweet (session `button-stands`, effort xhigh)

George, 2026-11-11, the evening 0.9.4 went out (he looks at the Mac's search field and at the "+" on his iPhone 16;
Rosé is his favourite theme, so Button is the creature he sees every day):

> Please don't be lazy and just have every creature with feet swing their feet as a part of their idle animations;
> the new mushroom creature certainly shouldn't be swinging his feet as he has tiny stubs for feet and it makes no
> sense for his character's vibe anyways. Each animation should match the vibe of its creature. The new mushroom
> should stand fully on top of the search bar and puff around or roll around, doing mushroom-related animations,
> whichever makes most sense for how you imagined his vibe. He's also a bit large and looks kind of creepy.

and, about the whole cast:

> It seems this turn you're starting to realize that these creatures can sit both in front of and behind certain
> elements on the Z-axis, making them feel more real, which is great (but no need to overdo it). Of course, some
> characters should definitely still hang down such as the creature with the long ears (Hush?) and the original
> sleepy creature and maybe a few others, but each character's positioning and idle animations should actually make
> sense with/act as flavor for that creature.

Button (`HITList/Support/Companions/Characters/Button.swift`, Rosé's companion since this afternoon) keeps its name,
its id, its theme and its rose cap with pale spots. Everything else is yours to redraw.

## What is wrong today (the supervisor's look at real size; look yourself before you draw)
`build.noindex/round-20/handover/09-button-the-mushroom.png` in the main checkout
(`/Users/gtrammell/Desktop/HITList/`), and 102's own pictures in the shared notes folder
(`102-rose-and-graphite/`).
- **Creepy:** a bone-white face, two large black diamonds for eyes and one black dot under them is a skull. The
  glints do not save it at 1x.
- **Large:** the cap fills all 20 pixels of the canvas; it is the widest and heaviest of the eight.
- **It sits and kicks:** boots dangle over the front of the "+", and half of its idles are boot kicks (`bootL`,
  `bootR`, `kicks`, `twinkleKick`, `winkKick`). A mushroom does not sit on a wall and swing its legs.

## Who Button is (the supervisor's idea of the vibe; make it better, keep it one idea)
A mushroom that sprouted on the bar overnight: tiny, round, a little bashful, planted where it stands. It bobs and
sways as if it were still growing, puffs itself up, lets go of a spore or two, and when it thinks nobody is looking
it tucks into its cap and rolls. It is the one creature of the eight that is glad of the rain.

## Do this first (within the first hour): concepts, then ask
Four different Buttons as stills (awake on the "+", awake on the Mac's field, asleep, one mid-idle), at 8x and at
real size on Rosé (the real "+" and the real field, not a flat rectangle), one line each on why it is sweet and
not creepy. `103-button-stands/concepts.png` in the shared notes folder; message the supervisor with your pick
(reply to the message that brought you this brief) and **carry on with your pick without waiting**; if the
supervisor answers with another pick or changes, switch. What every concept obeys:
- **Small.** The smallest of the cast: awake, cap and all, at most 14 pixels wide and 13 tall. (The canvas may stay
  20 × 20, or grow wider if rolling needs the room: `width` is the character's own.)
- **A face nobody could call a skull.** Not white on black holes. Small dark eyes set wide and low, each with a
  glint that still reads at 1x; cheeks; a tiny mouth or none; the stem a warm tone of the palette, not bone. Look at
  Hush, George's favourite, at real size first: one soft shape, a face you would pick up.
- **Standing.** Both stub feet on the host's top edge; nothing of it below the seat row, in any still. No boots.
- Original, always (`dev/SUPERVISOR.md` §7): nobody else's mushroom. Do not look other characters up. No white cap
  with big coloured spots over a face and a vest, no walking brown cap with a frown.

## Items (one commit each once the concept is chosen; film each at real size and look at it)
1. **The stills, both places** (the "+" on iPhone and iPad, the Mac's field): awake and asleep (the cap pulled down
   over the eyes was good: keep the idea), rain, snow and its depths, heat. Mushrooms come up after rain: in the rain
   Button stands a pixel taller and happier, a drop on the cap's rim. Snow piles on the cap. In the heat it wilts.
2. **Idles that only a mushroom would do.** Awake at least six flickers and four little loops
   (`Routine(little: true)`), asleep at least two breaths. No kick, no swing, no boot. To beat or to take: the cap
   bobs once like a nod; a sway from the root as if a breeze passed; it puffs up (cheeks and cap a pixel rounder)
   and lets the air go; a spot on the cap blinks like a light going on; it rises on its stubs to look and drops
   back; the cap tips forward as a hat does and back; a shiver that runs up the stem; it grows one pixel and thinks
   better of it. The plain blink stays the most common.
3. **Routines** (four or more, a flourish, an answer to a tap), the two George named among them:
   - **the roll**: it ducks under its cap, tips over and rolls a few pixels along the bar and back (the cap is
     round: it is the obvious wheel), then pops upright, dizzy for a beat;
   - **the puff**: it swells, holds, and lets go a puff of spores. The format's rule is that nothing is drawn in
     the air around a companion; **a spore puff is Button's own exception** (George: "puff around"): at most three
     pixels, within two pixels of its cap, gone within a second, never in rain or snow, never as an idle more
     often than once in a few minutes. The supervisor adds the exception to the format's header at the merge.
   Others to beat or take: a bounce on the spot that ends in a wobble; a spin of the cap like a top; planting itself
   again (a wriggle down, a settle).
4. **The seat.** Standing on the "+" where the capsule curves is harder than sitting: use `Posture(inset:)` to
   stand where the top is flat enough, and pass `CompanionSeatTests` (no background between its feet and the host
   in any still, iPhone 17 and 16 widths at 3x, the iPad, the Mac's field). `CompanionPerch.clearance` follows the
   drawing by itself.
5. Delete what the new Button no longer uses (the boot frames and gestures, their tests).

## What each still needs (the specification; read these)
`dev/briefs/COMMON.md` (the Round 21 block first); the format's header at the top of
`HITList/Support/Companions/CompanionCharacter.swift`; `dev/briefs/102-rose-and-graphite.md` (what Button was
asked to be this afternoon) and `100-companions-alive.md` (the pace: an idle every 6 to 36 s, little loops, the
seat and its check); the workshops in the shared notes folder (`102-rose-and-graphite/workshop/`,
`84-companion-routines/workshop/`: drawing, auditing, the seat, filming). Every palette, `problems` empty.

## Ownership
`HITList/Support/Companions/Characters/Button.swift`, `HITListTests/CompanionButtonTests.swift`, and the lines that
name Button's frames or gestures in the companions' shared tests. Not yours: every other character (104 redraws
Gargle now; 105 works on the other six), the engine (`CompanionCharacter.swift`, `CompanionDirector`,
`CompanionSchedule`, `Views/Companions/*`: 104 is adding a "behind the host" layer there; Button stands on top
and does not need it), `CompanionCast.swift`, `ThemeCompanion.swift` (say in your report where Button should stand
on Rosé's swatch in Settings; the supervisor sets it), Settings, `scripts/`, `dev/`, `CHANGELOG.md`, `WhatsNew.swift`.

## How to work
Draw first with the workshop's scripts; build once, late; your own simulator (`HITList-103`, an iPhone 16: George's
phone), your own side store. Look at every frame at real size, on the phone's "+" and on the Mac's field. Debug
arguments: `-companion button`, `-companionSky rain|snow|heat|storm`, `-companionSnowDepth 2`,
`-companionPlay routine[:name]`, `-companionHour 23`, `-pref.theme rose`.

## Done
The concept sheet; Button at 8x and at real size in every still on both platforms, beside this afternoon's; each
idle, loop and routine as a strip; a one-minute film strip awake and one asleep (frames of the moments something
moved, with their times); the seat check's output. The three suites green. The branch; one changelog line in plain
words; where it stands on its swatch; decisions George might reverse.
