# Brief 132: creatures that feel alive (session `alive`, effort xhigh)

George, 2026-11-14, on 0.9.9 (which he and his friends have):

> Also, my bad, but animations do have to happen more often; we made them too sparse. The creatures just feel idle
> now. Animations should happen at least once every like 12 seconds and at most once every 4-7 seconds with some
> randomness involved to feel natural. It's still okay to have creatures skip most of their idle animations during
> weather effects, they just need to feel a bit more alive in their default states (hopefully still without being
> too distracting). Perhaps they should also have task completion animations so they feel more associated with the
> app; that could be cool.

Read `dev/briefs/COMMON.md` (the Round 27 block first, then Round 26's standing rules and Round 25's and 24's
creature rules), `dev/briefs/ROUND-27.md`, then the engine: `Support/Companions/CompanionSchedule.swift` (today:
`idleGap = 6...36`, `firstIdle = 2...6`), `CompanionDirector.swift`, `CompanionClock.swift`,
`CompanionCharacter.swift`, `Views/Companions/*`, and `Views/Delight/CompletionDelightHook.swift`.

**You are the engine's one owner this round.** 133 is redrawing Flint's blink and rain in `Characters/Flint.swift`
and 134 is changing Phase's rain eyes in `Characters/Phase.swift` while you work: you never edit a file under
`Characters/`, and they never edit the engine. Frame, gesture and routine names in every character file stay as
they are (they have been told the same), so a cheer may name them.

## Items, in this order (one commit each, failing test first)
1. **The pace, in the default states.** Awake by day with no sky holding, and asleep at night: from the end of one
   idle to the start of the next the wait is never more than 12 seconds and never less than a floor that is itself
   drawn anew for each wait, between 4 and 7 seconds. So every wait lies in 4...12, most between 6 and 10, and no
   two waits in a row are equal. The first idle after coming on screen within 1.5 to 4 seconds. Pure, in
   `CompanionSchedule`, pinned by tests over a few hundred draws (bounds, a median between 6 and 10, the floor
   really varying). **Under a sky that holds** (rain, storm, snow, heat) the pace and what is skipped stay exactly
   as they are today: he said that is fine, and nobody is redrawing weather idles for a faster beat.
2. **Without being too distracting.** At three times today's rate the same blink wears: an idle is never one of
   the creature's last two when it has three or more to choose from; at least two in three are flickers (the
   small ones, 16 pixels at most); the plainest keeps the heaviest weight. Routines (every 3 to 8 minutes) and the
   flourish keep their rules. Reduce Motion: nothing moves. Low Power Mode and Reduce Effects: idles only, as now.
3. **A cheer when a task is completed.** `CompletionDelightHook` tells the director; the creature on screen plays
   its cheer, one to two seconds. Rules: follows Extras → Companions and no new setting; at most one cheer in any
   6 seconds (ten tasks ticked in a row cheer once, and again once 6 seconds have passed); never cuts a flourish
   or a routine short (it is dropped then); asleep, the creature plays its `answer` (the sleepy peek) at most once
   a minute instead; under a sky that holds, only if the creature has frames that carry that sky's water or snow
   (else its sky answer or nothing: a dry frame in the rain is a bug); un-completing a task plays nothing; the next
   idle's wait starts when the cheer ends. Shared tasks, the widget and Flipboard switches: completing a task in
   any list of the app counts; a switch flipped green counts too if the hook already fires there, otherwise leave
   switches out and say so.
4. **Each creature's cheer is its own, made of what George has already seen.** A table in a new file,
   `Support/Companions/CompanionCheers.swift`: character id → ticks naming that creature's existing frames (its
   glad ones: Flint's `happy`, `giggle`, `wingsUp`; pick the others by looking), checked by a test that every name
   exists. **No new drawings this round**: the six creatures George has signed off are frozen and two are being
   changed by siblings. What the engine may add is motion of the whole sprite for a tick (a hop of one or two
   pixels, if a per-tick offset is cheap and every other creature draws as before, pinned by a test). Nod is
   sleepy, Quill is a cat, Tuck is slow, Hush listens, Glim tends a lantern, Phase is sudden, Button is a
   mushroom, Flint is a gryphon cub: eight cheers that are not the same hop.
5. **The cost.** Round 26's rule: nothing endless, no timer with nothing pending, nothing scheduled while the
   companion cannot be seen. On the Mac the companion sits on the search field in the toolbar, where every frame
   of an animation lays the toolbar out again: measure before you change anything (`top -l 120 -s 1 -pid <pid>
   -stats pid,cpu` on your Debug Mac build with a companion idling, today's pace then yours) and give both
   averages and the reading between moves in the report. Between moves it must read 0.0%; the two-minute average
   must stay under 1.5%. If today's cost per move is high, say where it goes (`sample <pid> 5`) before anything
   else: the supervisor decides with you whether the sprite's hosting changes.

## The strip (due 21:05 Eastern)
One picture for George: each of the eight cheers as a strip of its frames at 3x on the "+" in the creature's own
theme, with the 1x under it, and a line saying what each does. Send the supervisor its path
(`mcp__ccd_session_mgmt__send_message`, `session_id: "parent"`) and carry on.

## Ownership
`Support/Companions/CompanionSchedule.swift`, `CompanionDirector.swift`, `CompanionClock.swift`,
`CompanionCharacter.swift` (only what a cheer or an offset needs), new `Support/Companions/CompanionCheers.swift`,
`Views/Companions/*`, `Views/Delight/CompletionDelightHook.swift` (the one call), `HITListTests/CompanionIdleTests`,
`CompanionDirectorTests`, `CompanionClockTests`, `CompanionSpriteTests`, a new `CompanionCheerTests`. Not yours:
anything under `Characters/`, `CompanionFlintTests`, `CompanionPhaseTests`, `ThemeCompanion.swift` (135), the sync
files and the bolt's views (the supervisor), Settings pages, `scripts/`, `dev/`, `CHANGELOG.md`, `WhatsNew.swift`.

## Done (report due 21:55 Eastern)
The pace and the cheer running on your Debug Mac app and on one iPhone simulator of your own (booted only after
20:45: siblings are booting theirs), a short screen recording or a contact strip of a minute at rest and of three
completions; the CPU numbers of item 5; `scripts/test.sh macos` and `ios` green (`core` if you touched it); the
report COMMON asks for, with the decisions George might reverse (the floor's range, the 6 seconds between cheers,
what plays asleep, which frames each cheer uses).
