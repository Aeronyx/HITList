# Brief 105: each creature moves like itself (session `cast-flavor`, effort xhigh)

George, 2026-11-11, the evening 0.9.4 went out (the companions idle every 6 to 36 seconds since this afternoon, so
he is now watching what they do):

> Please don't be lazy and just have every creature with feet swing their feet as a part of their idle animations;
> the new mushroom creature certainly shouldn't be swinging his feet as he has tiny stubs for feet and it makes no
> sense for his character's vibe anyways. Each animation should match the vibe of its creature.
>
> […] It seems this turn you're starting to realize that these creatures can sit both in front of and behind certain
> elements on the Z-axis, making them feel more real, which is great (but no need to overdo it). Of course, some
> characters should definitely still hang down such as the creature with the long ears (Hush?) and the original
> sleepy creature and maybe a few others, but each character's positioning and idle animations should actually make
> sense with/act as flavor for that creature.

The mushroom (Button) and the gargoyle (Gargle) are being redrawn tonight by sessions 103 and 104. **Yours are the
other six: Nod, Quill, Tuck, Hush, Glim and Phase.** This afternoon's brief asked for "enough idles to stay fresh"
and suggested the same list to everyone (a blink, a glance each way, a foot or tail swing, an ear twitch,
"blink-swing-swing"): that is the laziness George saw. Tonight each creature's idles are looked at one by one
against who that creature is.

This is a flavor pass, not a redraw. Nobody's resting picture changes unless the way it sits is wrong for that
creature; nobody is renamed; the pace stays (`CompanionSchedule`: an idle every 6 to 36 s, a routine every 3 to 8
minutes).

## Who they are (George's words where he has said any; the rest is the supervisor's reading: sharpen it)
- **Nod** (Slate), "the original sleepy creature": a child up past bedtime in a nightcap, legs over the edge.
  George: he should still hang down. Sleepy is the whole character: the head that droops and jerks up, the yawn,
  the rubbed eye, the bobble of the cap that swings after the head moves, legs that swing slow and out of step, as
  a tired child's do. A brisk two-footed kick is someone else's.
- **Quill** (Midnight): a writer's cat with an inked tail tip, lying along the bar. George (round 19): "Quill's butt
  should slope like it's hanging off the side of the 'Add task' button when he's lying down". A cat's own: the slow
  blink, one ear turning to a sound, the tail tip that writes a small stroke and flicks, kneading, a paw washed,
  eyes that follow something only it can see, the loaf.
- **Tuck** (Moss): a snail with a potted seedling. George: "the Moss snail is cute". A snail's own: eye stalks
  that draw in one after the other and come back, half a retreat into the shell at a fright, a slow lean toward
  the seedling, the seedling's leaf that lifts when he looks at it. Nothing fast.
- **Hush** (Nord), George's favourite and the standard for cute: the creature with the long ears, which hang down
  the front of the host with her feet. George: she should still hang down. Her own: one ear lifted to listen and
  let fall, the ears that swing a beat behind the head, the nose, hiding her eyes behind an ear, shy.
- **Glim** (Tokyo Night): a mouse with a lantern on a stick, the lantern hanging in front of the button. A mouse's
  and a lamplighter's own: whiskers, a sniff of the air, the lantern lifted to peer at something, the flame that
  gutters and is cupped back to life, the lantern set swinging and stilled with a paw.
- **Phase** (Mocha): the sneaky, see-through ghost George asked for, half inside the button. Mischief is the
  whole character: the side-eye, the sink to the eyes and the rise, going a shade more see-through, popping up a
  little further along, the tongue.

## Items (one commit per creature; film each at real size and watch it)
1. **The audit, first, as a table per creature** (`105-cast-flavor/audit.md` in the shared notes folder): every
   flicker, little loop and routine it has today, what it shows, and one of *its own* (only this creature would do
   it), *plain* (a blink, a breath: every creature has them, and they stay the most common) or *generic* (any
   creature with the same limbs could do it). Watch two minutes of each creature at real size before you judge.
2. **Then, creature by creature:** every *generic* idle is redrawn into something of its own or removed, and each
   creature ends with **at least three idles and two routines that only it would do**, drawn so they read at 1x
   (film them; a move of one pixel that nobody can see is not an idle). Timing is part of character: Nod and Tuck
   are slow, Glim is quick, Phase is sudden. Awake each keeps at least six flickers and four little loops, asleep
   at least two breaths, and the rules of the format (`problems` empty for all).
3. **How each sits, checked against who it is** (the table gets a line per creature: hangs, lies, stands, is half
   inside, and why). Change a seat only where it is wrong for the creature, and say what you changed. Things in
   front of the host stay where they make sense (Nod's legs, Hush's ears and feet, Glim's lantern).
4. **Behind the host, sparingly.** Session 104 is adding a "behind" layer to the format tonight (a pixel drawn only
   where the host is not); the supervisor will message you when it is on master: then `git merge master`. George:
   "great (but no need to overdo it)". Use it only where it makes one creature more real (the far end of Quill's
   tail, Phase popping up from behind the button), at most two creatures, or not at all, and say why.
5. `CompanionSeatTests` passes for every still you touch; the one-minute test of this afternoon still passes
   (`CompanionDirectorTests.testNeverADeadMinute`).

## What you need to read
`dev/briefs/COMMON.md` (the Round 21 block first); the format's header at the top of
`HITList/Support/Companions/CompanionCharacter.swift`; `dev/briefs/100-companions-alive.md` (this afternoon's
contract and its seat check) and session 100's notes in the shared notes folder (`100-companions-alive/`: its
idles list, its films); the workshops (`84-companion-routines/workshop/`, `102-rose-and-graphite/workshop/`:
drawing, auditing, the seat, filming).

## Ownership
The character files `Nod.swift`, `Quill.swift`, `Tuck.swift`, `Hush.swift`, `Glim.swift`, `Phase.swift` under
`HITList/Support/Companions/Characters/`, their own test files (`CompanionTuckTests`, `CompanionGlimTests`,
`CompanionPhaseTests`, a new one for a creature that has none) and the lines that name their frames or gestures in
the companions' shared tests. Not yours: `Button.swift` (103), `Gargle.swift` (104), the engine
(`CompanionCharacter.swift`, the schedule, the director, the clock, `Views/Companions/*`: 104 edits it tonight; a
change you need there goes to the supervisor as a message), `CompanionCast.swift`, `ThemeCompanion.swift`, Settings,
`scripts/`, `dev/`, `CHANGELOG.md`, `WhatsNew.swift`.

## How to work
Draw and audit with the workshop's scripts first; build once per platform, late; your own simulator (`HITList-105`,
an iPhone 16: George's phone), your own side store. Film at real size (the simulator at 3x, the Debug Mac app at
2x). Debug arguments: `-companion <id>`, `-companionSky rain|snow|heat|storm`, `-companionPlay routine[:name]`,
`-companionHour 23`, `-pref.theme <slate|midnight|moss|nord|tokyo|mocha>`.

## Done
The audit table, before and after; for each of the six, its new or redrawn idles as strips at 8x and at real
size, and a two-minute film strip awake (frames of the moments something moved, with their times) that a person
could tell from the other five with the creature hidden. The three suites green. The branch; changelog lines in
plain words; decisions George might reverse.
