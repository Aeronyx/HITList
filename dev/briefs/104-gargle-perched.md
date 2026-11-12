# Brief 104: Gargle perched and carved, his tail behind the bar (session `gargle-perched`, effort xhigh)

George, 2026-11-11, the evening 0.9.4 went out (he looks at the Mac's search field and at the "+" on his iPhone 16):

> Then, the new bat-looking creature also looks a bit lazy visually/like a grey blob (he's not too bad though) and
> doesn't need to be hanging his feet over the search bar either. His tail also should be behind the search bar/Add
> task button, not in front of it. It seems this turn you're starting to realize that these creatures can sit both
> in front of and behind certain elements on the Z-axis, making them feel more real, which is great (but no need to
> overdo it). Of course, some characters should definitely still hang down such as the creature with the long ears
> (Hush?) and the original sleepy creature and maybe a few others, but each character's positioning and idle
> animations should actually make sense with/act as flavor for that creature.

and, about the whole cast:

> Please don't be lazy and just have every creature with feet swing their feet as a part of their idle animations
> […] Each animation should match the vibe of its creature.

Gargle (`HITList/Support/Companions/Characters/Gargle.swift`, Graphite's gargoyle pup since this afternoon) keeps his
name, his id and his theme. George's verdict is "not too bad": this is a second pass on the same creature, not a
new one.

## What is wrong today (the supervisor's look at real size; look yourself before you draw)
`build.noindex/round-20/handover/10-gargle-the-gargoyle-pup.png` in the main checkout
(`/Users/gtrammell/Desktop/HITList/`), and 102's pictures in the shared notes folder (`102-rose-and-graphite/`).
- **A grey blob:** head and body are one flat mid-grey shape with no neck, no muzzle, no shading; the wings are
  two dark triangles at the sides that read as arms; the white horn tips are the only detail. From a step back it
  is a grey cat, or a bat ("the new bat-looking creature"). Nothing says stone, nothing says gargoyle.
- **He sits like the others:** two feet over the front of the host, as Nod's and Hush's. A gargoyle perches.
- **His tail hangs down the front** of the "+" and of the field, one grey hook over the button's face.

## Who Gargle is (the supervisor's idea of the vibe; make it better, keep it one idea)
A gargoyle pup carved for a ledge and come half alive on it: he crouches on the bar as his elders crouch on a
cornice, all four paws on top, wings folded up behind his shoulders, his tail dropped behind the bar with only its
tip coming back up over the edge further along. Half statue, half puppy: he holds very still, and then he is a pup
again.

## Item 1, first and on its own (one commit; then message the supervisor its hash): the "behind" layer
A companion is one sprite drawn over its host, so everything below its seat row lies on the host's face. Give the
format a way to say **this pixel is behind the host**: it is drawn only where the host's shape is not
(`CompanionPerch.surface`, the shape the seat already uses), so a tail that drops behind the "+" shows down to the
button's curve and no further, and behind the Mac's field it ends at the field's top edge.
- How a frame marks it is yours. The supervisor's suggestion: a capital ink letter is that ink behind the host
  (`M` is `m` behind), which keeps a frame one grid and needs no second picture. Document it in two lines of the
  format's header at the top of `CompanionCharacter.swift`.
- Additive and small: no other character's frames change, `problems` still passes for all eight (teach it the new
  marks: a behind pixel above the seat row is a mistake), the seat (`CompanionSeat`) and the tap area ignore behind
  pixels, see-through inks keep working, Reduce Motion is unaffected.
- The swatch miniature in Settings (`ThemeCompanionSprite`, the supervisor's file) draws a companion with no host:
  give `CompanionSprite` what it needs so that a behind pixel below the seat row is simply not drawn there, with
  no change at the call site, or tell the supervisor the one line to add.
- Tests: a frame with behind pixels on the real "+" at iPhone 17 and 16 widths and on the Mac's field: none of
  them is drawn inside the host's shape, all of them outside it are.
- Build both platforms' test bundles before you send the hash (a Mac-only symbol in a test broke the iOS bundle
  for three sessions this afternoon). Session 105 (the other six creatures) may use the layer once it is on master.

## Item 2 (within the first hour, beside item 1): concepts, then ask
Three or four Gargles as stills (awake on the "+", awake on the Mac's field, asleep, one mid-idle), at 8x and at
real size on Graphite (the real "+" and the real field), one line each on what makes it read as a small stone
gargoyle and what makes it sweet. `104-gargle-perched/concepts.png` in the shared notes folder; message the
supervisor with your pick (reply to the message that brought you this brief) and **carry on with your pick without
waiting**; if the supervisor answers with another pick or changes, switch. What every concept obeys:
- **Carved, not flat.** A head that is clearly a head (a notch or a shadow under the chin, a short muzzle or a brow
  ridge), two tones of stone and a highlight (`dark` under the chin and the belly, `light` on the brow, the horn
  tips and the wing ribs), wings that are wings (folded up behind the shoulders, a rib line, a hooked tip), toes.
  One small detail may take the theme's accent (Graphite's is the cream of the "+"). Keep what is good: the large
  eyes with their glints, the horns, the small tongue.
- **Perched.** The gargoyle's crouch: haunches up, front paws down between the hind feet, all on the host's top
  edge. Nothing of him in front of the host. No dangling feet.
- **The tail goes behind** (item 1): down behind the bar from his rump, and its tip (a spade, an arrow, a tuft:
  yours) comes back up over the edge a few pixels along, where it can twitch. On the "+" the tail shows down to the
  button's curve at its shoulder. That tip is what tells the eye the rest is behind.
- From a step back at 1x it must read "little stone gargoyle", not cat, not bat, not owl.
- Original, always (`dev/SUPERVISOR.md` §7): nobody else's gargoyle or dragon. Do not look other characters up.

## Items after the concept (one commit each; film each at real size and look at it)
3. **The stills, both places**: awake and asleep ("turned to stone": curled, a shade paler, was a good idea: keep
   it), rain (a gargoyle is a rain spout: the drop falls from his chin), snow and its depths (between the wings),
   heat (flat on the cool stone).
4. **Idles that only a gargoyle pup would do.** Awake at least six flickers and four little loops
   (`Routine(little: true)`), asleep at least two breaths. No foot swing. To beat or to take: he goes stock still
   and a shade paler for a beat, then one eye opens; the tail's tip rises from behind the bar like a periscope,
   looks one way and sinks; a wing shrugs open and folds; a crumb of stone drops from a horn and he watches it go;
   a yawn with one small fang; an ear-scratch with a hind paw, as a pup does; a head tilt; a sniff along the ledge.
   The plain blink stays the most common.
5. **Routines** (four or more, a flourish, an answer to a tap): the statue game (he freezes when he thinks he is
   watched, then peeks); a stretch that opens both wings and nearly lifts him; chasing the tail tip that keeps
   appearing behind the bar; shaking off dust or snow. Keep what was good among today's (`statue`, `tryFly`,
   `flop`), redrawn.
6. **The seat**: `CompanionSeatTests` for every still (iPhone 17 and 16 widths at 3x, the iPad, the Mac's field).
7. **Later, on the supervisor's message only** (it depends on session 106, which is rearranging the iPhone Duo's
   outer display tonight): the companion's place on the Duo's outer display, where the "+" stands upright under
   the tab island and has no companion today (`IslandAddButton`). The message will say where it sits; until then
   leave the Duo alone.

## What each still needs (the specification; read these)
`dev/briefs/COMMON.md` (the Round 21 block first); the format's header at the top of
`HITList/Support/Companions/CompanionCharacter.swift`; `dev/briefs/102-rose-and-graphite.md` (what Gargle was asked
to be this afternoon) and `100-companions-alive.md` (the pace: an idle every 6 to 36 s, little loops, the seat and
its check); the workshops in the shared notes folder (`102-rose-and-graphite/workshop/`,
`84-companion-routines/workshop/`: drawing, auditing, the seat, filming). Every palette, `problems` empty.

## Ownership
`HITList/Support/Companions/Characters/Gargle.swift`, `HITListTests/CompanionGargleTests.swift`; for item 1 the
frame parsing and `problems` in `CompanionCharacter.swift`, `Views/Companions/CompanionSprite.swift`, the figure,
seat and tap area in `Views/Companions/CompanionPerch.swift`, and a test file of your own; the lines that name
Gargle's frames or gestures in the companions' shared tests. Not yours: every other character (103 redraws Button
now; 105 works on the other six), the schedule, the director and the clock, `CompanionCast.swift`,
`ThemeCompanion.swift` (say in your report where Gargle should sit on Graphite's swatch in Settings; the
supervisor sets it), `Views/Tabs/*` and `Views/Duo/*` (106), Settings, `scripts/`, `dev/`, `CHANGELOG.md`,
`WhatsNew.swift`.

## How to work
Item 1 needs a build; do it first and small. Then draw with the workshop's scripts and build once more, late; your
own simulator (`HITList-104`, an iPhone 16: George's phone), your own side store. Look at every frame at real size,
on the phone's "+" and on the Mac's field. Debug arguments: `-companion gargle`,
`-companionSky rain|snow|heat|storm`, `-companionSnowDepth 2`, `-companionPlay routine[:name]`, `-companionHour 23`,
`-pref.theme graphite`.

## Done
The behind layer's hash sent early; the concept sheet; Gargle at 8x and at real size in every still on both
platforms, beside this afternoon's; each idle, loop and routine as a strip; a one-minute film strip awake and one
asleep (frames of the moments something moved, with their times); the seat check's output. The three suites green.
The branch; one changelog line in plain words; where he sits on his swatch; decisions George might reverse.
