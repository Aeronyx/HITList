# Brief 100: the companions are alive, and they sit (session `companions-alive`, effort xhigh)

George, 2026-11-11, after a morning with 0.9.3 on his phone:

> About the creatures: I started at my phone screen for like a whole 60 seconds and he didn't move a muscle, which
> just makes them feel dead. We still need either single idle animations or small custom animation loops at least
> every ~30-40sec and at most every ~5-10seconds.
>
> […] the Moss snail is cute, but needs a glint in his eye or something to seem a bit less soulless. […]
>
> And, some of them still don't sit on the "Add task" button quite right; they shouldn't look like they're floating
> above it or simply superimposed on top of it.

and what he asked for the night before, which the last round under-delivered (`dev/briefs/ROUND-19.md`):

> have it so that a group of gestures (blink, a few leg swings, sometimes a little readjustment, etc.) play in
> quick succession, and then he can return to being idle/only blinking or swinging a foot now and then.

So "idle" was never meant to be a still picture: it is **blinking or swinging a foot now and then**, every few
seconds to every half minute, with the longer routines as the rare treat. Today a flicker comes every 40 to 110 s
(`CompanionSchedule.flickerGap`) and asleep a stir every 6 to 15 minutes: that is the dead minute George watched.

Read `dev/briefs/COMMON.md` (Round 20 block first), `dev/SUPERVISOR.md` §7, the format's header at the top of
`HITList/Support/Companions/CompanionCharacter.swift`, `CompanionSchedule.swift`, `CompanionDirector.swift`,
`Views/Companions/*`, and last night's workshop (the shared notes folder, `84-companion-routines/workshop/`: the
drawing, auditing and filming scripts, the "+" capsule's real geometry). Sessions 101 (`phase`) and 102
(`rose-and-graphite`) are drawing three new characters against the contract below while you work.

## The contract (already on master: `Routine.little`; the rest is yours, first, as one commit)
```swift
enum CompanionSchedule {
    /// Showing time between one idle and the next, awake or asleep.
    static let idleGap: ClosedRange<TimeInterval> = 6...36
    /// The first idle after a companion comes on screen (launch, back to the app, its tab, a sheet closing).
    static let firstIdle: ClosedRange<TimeInterval> = 2...6
    static let routineGap: ClosedRange<TimeInterval> = 180...480     // was 300...720
}
struct Routine { … var little = false }   // a little loop: 2 to 4 moves, at most 2.5 s; `problems` checks it
```
- **An idle** is one flicker (about two in three) or one little loop (about one in three): never the same one
  twice running, the plainest (a blink) the most common by weight, the weather's own taking their share as today
  (`skyFlickerShare`). `flickerGap` and `stirGap` go.
- **Asleep** it breathes at the same pace: a mode's flickers are its breaths, a twitch, a murmur; the old stir is
  one of them. No routines asleep, as today.
- **The first idle comes 2 to 6 s after it comes on screen**, so a ten-second visit sees it move. The flourish
  keeps its own settling time and its rarity; the long routines keep their clock (now 3 to 8 minutes of showing
  time, kept across launches) and are never little ones. Taps as today.
- Reduce Motion: nothing moves. Reduce Effects and Low Power Mode: idles only. Nothing runs while nothing plays
  (no timer between events beyond the one that starts the next).
- Tests on a simulated clock: ten minutes awake and ten asleep with no still stretch longer than 36 s plus the idle
  before it; the first idle within 6 s of each way of coming on screen; never twice the same running; the shares;
  a character with one flicker and no loops still works; Reduce Motion.
- **Then message the supervisor the commit's hash** (reply to the message that brought you this brief), so it can
  go to master for the other two sessions, and carry on.

## Items after the engine (one commit each; film each at real size and look at it)
1. **Enough idles to stay fresh at this pace**, for Nod, Quill, Tuck, Hush and Glim, in both places: awake at
   least five flickers and three little loops each (a blink, a slow blink, a glance each way, a foot or tail
   swing, an ear or antenna twitch, a breath; loops such as blink-swing-swing, glance-glance-settle, a small
   stretch), asleep at least two. Each belongs to that creature: ask what this one would do. Twenty seconds apart,
   three flickers would repeat every minute; that is the next complaint if you stop at the minimum.
2. **The seat.** On the "+" (a continuous capsule: its top curves away under a flat base) a companion must look
   like it is sitting on the button: at real size there is no background between the creature and the "+"
   anywhere along where they meet, its base follows the curve or is tucked behind the rim, feet, legs or a tail
   may hang over the front, and a contact shadow in the capsule's own colour is allowed where it helps. Never a
   flat base floating on a chord (Tuck today: dark shows under both ends of his base), never a sprite merely laid
   over the button's face. George, the night before: "Quill's butt should slope like it's hanging off the side of
   the 'Add task' button when he's lying down, not floating above it": check that it does.
   - Make the check: render each character on the real "+" in every still (rest, rain, snow and each depth, heat,
     asleep), in each theme, at iPhone 17 and iPhone 16 widths, and measure the gap column by column; the same on
     the Mac's search field (a 1 pt gap shows under Tuck there too). Put it where sessions 101 and 102 can run it
     on theirs (a test every character must pass, and the script in the workshop folder), and tell the supervisor
     when it exists.
   - Fix the five. Before and after at 8x and at real size, each still.
3. **Tuck's eyes.** His stalk eyes are hollow squares. Give them life: pupils with a glint, eyes that look where
   he is going, half-close when he smiles, and a glance among his idles. Keep everything else George called cute.
4. **The end of a list.** On iPhone the companion on the "+" covers the trailing end of the last row (Browse's
   Settings chevron, a Shared Tasks count): at the end of every scrolling screen the last row can be scrolled
   clear of the "+" and of a companion on it (the bottom inset grows by what shows). One line where the lists take
   their bottom inset; brief 99 owns the rest of those files.

## Ownership
`HITList/Support/Companions/CompanionSchedule.swift`, `CompanionDirector.swift`, `CompanionClock.swift`, the engine
parts of `CompanionCharacter.swift` (not the inks or how a sprite is drawn: session 101 adds see-through ink
there), `Views/Companions/*` except the drawing lines 101 touches in `CompanionSprite.swift`, the character files
`Nod`, `Quill`, `Tuck`, `Hush`, `Glim`, the companions' engine tests, the lists' bottom-inset line. Not yours:
`Mallow`, `Posy`, `Smudge` and their replacements, `CompanionCast.swift` (101 and 102 change their own lines),
`ThemeCompanion.swift` (the supervisor's), `CompanionSky*.swift`, `Services/Weather/*`, Settings, `scripts/`,
`dev/`, `CHANGELOG.md`, `WhatsNew.swift`.

## How to work
Draw and audit with the workshop's scripts first; build once per platform; film at real size (the simulator at 3x,
the Debug Mac app at 2x) and watch a whole minute of each character before you call it done: that minute is the
test George ran. Debug arguments: `-companion <id>`, `-companionSky rain|snow|heat|storm`, `-companionSnowDepth 2`,
`-companionPlay routine[:name]`, `-companionHour 23`.

## Done
The schedule's table (what plays, how often, awake and asleep). For each of the five: its idles listed, a
one-minute film strip (frames of the moments something moved, with their times), and the seat before and after in
every still on both platforms. The check's output for all eight characters as they stand on master. All three
suites green. The branch; changelog lines in plain words; decisions George might reverse.
