# Brief 91: the weather shows on the creature (an addition to briefs 84, 85 and 87 to 89; effort as each session's)

George, 2026-11-11, 03:05, with eight companions being drawn:

> I was going to ask to also add in little weather effects around the creatures themselves, but I realized that's
> definitely going too far. Instead, what if we just have water drip off their umbrellas and stuff, or have them
> shake off in the rain, or have snow pile up on some of them, or have some of them get tired in the heat/try to
> hide in the shade, etc. so it really sells the weather effects more.

So: **nothing is drawn in the air around a companion** (no falling rain, no drifting snow, no sun rays; brief 84's
"a few drops or flakes may fall inside the sprite's own box" is withdrawn, except a single drop or flake the
creature itself touches: one running off the rim of what it holds, one landing on a nose). **The weather is told by
the creature**: what it holds drips, it shakes itself dry, snow gathers on it until it brushes it off, on a hot
day it wilts or finds its own shade. Rare, as everything a companion does (COMMON).

## What is already on master (the supervisor's, 03:30)
`CompanionSky.heat`: a hot day with nothing falling (by day, when it feels like 30 °C / 86 °F or more; rain, snow
and storms win; the weather service reports it; `-companionSky heat` and `-seedDemoSky heat` force it).
`CompanionLook.Weather.init` maps it to `.plain` until the engine below gives it a look.

## The engine (session 84 only; one commit, first, before your characters; additive: a character that uses none
## of it still compiles and behaves as it does)
The contract every character session writes against. Keep these names; if one must change, say so in your report.
```swift
struct Gesture {
    …
    /// The sky it belongs to: a drip in the rain, a bead of sweat on a hot day. Nil: every sky.
    var sky: CompanionSky? = nil
}
struct Routine {
    …                                 // `sky:` exists; it now also takes `.heat`
    /// It ends with the snow shaken off: the still frame is `snow` again, the first of the pile.
    var shakesOff = false
}
struct Mode {
    …
    var heat: String?                 // the still frame on a hot day (awake; asleep too if a character draws one)
    var snowDeep: [String] = []       // snow piling up: the still frames after `snow`, shallow to deep
}
enum CompanionLook.Weather { case plain, rain, snow, heat }   // `.heat` from `CompanionSky.heat`
```
- **Heat**: the still frame is `heat ?? rest`; routines and flickers with `sky: .heat` take about every other slot
  while it holds, as the rain's and snow's do.
- **A gesture with a sky** plays only under it (`.rain` also in a storm), on its own if it is marked `flicker`
  (about every other flicker while the sky holds). Its frames are the weather's own, drawn whole.
- **Snow piles up**: in snow the still frame starts at `snow` and moves one frame deeper through `snowDeep` after
  every 8 to 14 minutes of showing time (at random), stopping at the last. A routine with `shakesOff` ends on
  `snow` again. The depth is the companion's, kept in memory: it starts again when the sky leaves snow, on a new
  launch, and when night and day change over. Asleep in the snow a mode's own `snowDeep` piles the same way and a
  stir does not shake it off. A gesture or routine drawn for the bare `snow` frame is not played over a deeper
  frame unless it leaves the pile's pixels alone or a frame named for that depth exists (decide the rule, test it,
  explain it in the format's header in three lines).
- `problems` checks the new pieces (frames exist, the same size, the line where it meets the "+" unchanged by a
  pile); Debug: `-companionSnowDepth 2` beside `-companionSky`. Tests: a snowy hour (the pile grows, a shake-off
  starts it again), the rain's share of flickers, heat by day only, a character that uses none of it.
- Then tell the supervisor the commit so the other sessions can merge it: reply to the sender of the message that
  brought you this brief with one line (the hash), and carry on with your characters.

## Every character (84: Nod, Quill, Hush; 85: Posy, Mallow; 87, 88, 89: your own)
Each in its own way; these are George's four ideas, and a character takes each one that suits it (say why where
one does not):
1. **Rain: water on it.** If it holds or wears something in the rain, a drop gathers on the rim and falls (a
   flicker with `sky: .rain`). Its rain routine is a shake-off, or ends in one: wet, then a shake from head to
   tail, then dry-ish and settled. Check the routine you have against this and redraw it if it only looks up.
2. **Snow: it piles up.** Two deeper still frames (`snowDeep`) wherever snow would sit (a cap, a back, a pair of
   ears, a shell, a lantern): a dusting, then a cap, then a heap that almost hides something. A snow routine with
   `shakesOff` sends it off in one go (the pile jumps, slides, is gone) and it starts again. Asleep, the pile can
   grow too, if a sleeping pile is funnier.
3. **Heat: tired, or in the shade.** A hot-day still (`heat`): wilted, sprawled, ears or hat or wings turned into
   shade, a tongue out. One heat flicker (a bead of sweat, a pant, one slow fan) and one heat routine (it fans
   itself, gives up, flops; it pulls its hat down; it looks for the shade of its own tail). No two alike if you
   can help it: ask what *this* creature would do.
4. **"etc."**: one more of your own if a sky suggests it (a start at thunder exists; a stretch in the first sun
   after rain), only if you love it.
Everything else in your brief stands: nothing floats, both places, every palette, `problems` empty.

## How this reaches you
- **84**: this is your next pass, engine first.
- **85, 87, 88, 89**: draw the frames now with your scripts (the stills, the pile, the drip, the shake, the heat),
  and write them into your character against the contract above. It will not compile until the engine is on
  master: the supervisor messages you when it is; then `git merge master`, build, run the Mac suite, and look at
  each sky in the real app (`-companionSky rain|snow|heat`, `-companionSnowDepth`). One commit or two; then your
  report, with the new frames at 8x and at real size and each weather routine as a strip.
