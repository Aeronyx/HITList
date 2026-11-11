# Brief 84: companions that come alive now and then (session `companion-routines`, effort max)

George, 2026-11-11, on 0.9.2:

> As for your animation rarity settings, instead of making it so that only one small gesture plays every once in a
> while, have it so that a group of gestures (blink, a few leg swings, sometimes a little readjustment, etc.) play in
> quick succession, and then he can return to being idle/only blinking or swinging a foot now and then. In this way,
> each creature can have cute unique loops of animations but only every once in a while so that they stay fresh.
> This is almost the same way that game characters like Mario from Super Mario 64 work when left idle.
>
> […] Hush is awesome as you confirmed. Quill's butt should slope like it's hanging off the side of the "Add task"
> button when he's lying down, not floating above it.
>
> […] and then we can use that for weather effects/weather-related animations for each creature while they're
> awake.

Read `dev/briefs/COMMON.md` (Round 19 block first), `dev/briefs/ROUND-19.md`, `79-companion-cast.md` (everything
there still holds except its rule 1's "one small gesture every 45 to 120 seconds" as the whole of a companion's
life) and `76-companions.md` ("The characters are ours": original characters only; do not look for or work from
other people's character art. George names a game for the *idea* of an idle routine: a character left alone does
a short sequence that shows who it is, then settles. Take the idea; study no one's frames.) Then the engine:
`HITList/Support/Companions/*`, `HITList/Views/Companions/*`, and `Nod.swift`, `Quill.swift`, `Hush.swift`.

## The rules
1. **Three kinds of life, most of the time none.**
   - *Still*, by default. Nothing loops.
   - *A flicker*, now and then: one blink or one swing of a foot, the smallest things a character has. Each
     character marks which of its gestures are flickers. One every 40 to 110 seconds.
   - *A routine*, every so often: for a few seconds it comes alive. A scripted run of four to nine small moves in
     quick succession with short held beats between them (a blink, two or three leg swings, a shuffle to get
     comfortable, a look about, a stretch, a yawn, a fix of the hat), three to seven seconds in all, ending exactly
     on the rest pose. Each character has **at least three routines of its own** that could belong to nobody else,
     never the same one twice running. A routine comes after 5 to 12 minutes of *showing time* since the last one
     (at random; showing time as the flourish counts it, kept in the app group's defaults across launches, so
     opening the app for a minute twenty times does not play twenty routines).
   - *The flourish* stays as rare as it is (brief 79's numbers) and is not a routine.
2. **Routines are data.** A routine is written in the character's file as a list of steps (a gesture by name, a
   hold, a frame or two of its own) so a new character needs no engine work. Draw the in-between frames a routine
   needs (the readjustment is new drawing, not a blink played twice). **The format is additive**: a character with
   no routines and no flicker marks still compiles and behaves as it does today (brief 85's two new characters are
   drawn in today's format while you work and get their routines afterwards). Put the format's explanation, thirty
   lines at most, at the top of `CompanionCharacter.swift`: brief 85 writes its routines from that alone.
3. **The weather, awake.** The still looks for rain and snow stay. On top, by sky
   (`CompanionSkySource.shared.sky`):
   - rain: a rain routine of its own (a drop lands and it shakes it off, it peers out from under what it holds…);
   - snow: a snow routine (a flake caught, snow brushed from a hat or an ear);
   - storm: the rain look, plus a small start at thunder, rarely;
   - clear, by day: one small routine if you find one you love (a bask, a squint); none is fine;
   - clouds and unknown: nothing.
   While a sky holds, its routine takes about every other routine slot. A few drops or flakes may fall inside the
   sprite's own box *during* a weather routine; there is never a standing rain or snow effect (whatever moves by
   itself is rare).
4. **A tap gives a little more.** As today, a tap plays the flourish if none has played for 20 minutes. Sooner
   than that, a tap plays a routine if none has played in the last three minutes, else the small answer (at most
   every ten seconds, as today). Asleep: the stir, as today.
5. **The hours of where the person is.** Night (22:00 to 07:00) and day are read in
   `CompanionSkySource.shared.zone` (the supervisor's seam: brief 83 sets the zone of the place the weather was
   read for; it is the device's zone otherwise). Read it; do not edit that file.
6. **Nothing floats.** George: "Quill's butt should slope like it's hanging off the side of the 'Add task'
   button when he's lying down, not floating above it." The "+" is a capsule: its top edge curves down at both
   ends. Redraw Quill's lying poses for the "+" so the hindquarters and tail follow the curve down the right-hand
   shoulder, resting on it. Then check **every pose of every companion in both places at 2x and 3x**, in your
   simulator and on the Debug Mac app, pixel by pixel at the line where creature meets button or field: no row of
   background between them, nothing sunk into the button, feet and hanging things where gravity puts them. Fix
   what you find, by drawing or by the perch's offsets.
7. **Quiet, as before**: no sound, hidden from VoiceOver, nothing while its screen is hidden or the app is not in
   front, one timer at most (schedule the next event, do not tick). Reduce Motion: the still pose, nothing else.
   Low Power Mode and Reduce Effects: flickers only. Asleep: no routines. Extras → Companions turns it all off.
8. **Debug**: `-companionPlay routine` (cycles them), `-companionPlay routine:<name>`, beside the arguments that
   exist; `-companionSky`, `-companionHour` and `-companionZone` already force the sky, the hour and the zone.

## Items (one commit each)
1. **The engine**: flickers, routines, the showing-time budget and its kept value, the weather's share, the tap,
   the zone; pure and tested (`CompanionSchedule`, `CompanionDirector`, `CompanionClock`): a simulated eight-hour
   day's timeline, a simulated month's gaps, twenty one-minute visits, the same routine never twice running, a
   character with no routines, Reduce Motion, Low Power, asleep.
2. **Nod**: three routines or more, rain, snow, the storm start. George's favourite: his legs are who he is.
3. **Quill**: the "+" poses redrawn (rule 6), routines, weather.
4. **Hush**: routines, weather. Its ears are who it is.
5. **Nothing floats**, for all three in both places, with the before and after crops.

## Ownership
`HITList/Support/Companions/*` except `CompanionSkySource.swift` (the supervisor's), `CompanionCast.swift` and
`Characters/Pip.swift` (brief 85 replaces Pip and edits the cast: do not touch either, and do not add routines to
Pip); `HITList/Views/Companions/*`; `Characters/Nod.swift`, `Quill.swift`, `Hush.swift`; an `extension Preferences`
of your own for the kept times; `HITListTests/Companion*Tests.swift` (not `CompanionSkySourceTests.swift`; leave
any line that names Pip exactly as it is: 85 changes those lines); `HITListUITests/CompanionsUITests.swift`.
Not yours: new character files and the cast (85), every Settings view and the theme swatches (86 puts a small
still sprite on each theme with `CompanionSprite`: keep its initialiser and `CompanionInks(palette:)` working as
they are), `Services/Weather/*` (83), core, `HITListWidgets/*`, `dev/ROADMAP.md`, `CHANGELOG.md`, `WhatsNew.swift`.

## Done
For Nod, Quill and Hush: every new frame at 8x and at real size; each routine as a strip of frames with its
timing, recorded from the app (COMMON says how), in both places; the weather routines the same way. The timeline
of a simulated day from the tests (flickers, routines, flourishes, night). The "nothing floats" crops, before and
after, 2x and 3x. All three suites green, your UI tests on a fresh simulator. In the report, the numbers George
may want to turn (how often a flicker, how often a routine, how long), each with the one line that changes it.
