# Brief: Flipboard polish: start red, flip sound, verified in video

Effort: Medium. Model: Opus 5.5. Read `briefs/COMMON.md` first.

## Why
George's model of the board: a switch is red while the chore is not done. Add "Shave" with a two-week
interval and it starts red; flip it and it stays green until two weeks pass, then turns red until you
shave again. Today a new switch starts green (`createSwitch` and `add` give it one interval of credit),
which reads as "already done". Also: switches should make a light-switch sound.

## Files you own
`HITList/Views/Flipboard/` (all files), `HITList/Resources/Sounds/flip.caf` (new),
`HITListTests/FlipboardTests.swift`. Nothing else: do not touch Settings, Delight, or shared views.

## Task, three commits
1. **Start red.** `Flipboard.createSwitch` and `Flipboard.add` (when the task has no future due date)
   set `dueDate = today` so the switch is red with the caption "Flip to start", and the light bar empty.
   A task added with a future due date keeps it (green). The flip rule stays: a flip restarts the full
   interval from the flip day. Update `testCreateSwitchStartsGreen` and friends; add a test for the
   two-week scenario: create → red; flip → green, "0 of 14 days", due = today + 14; with `now` advanced
   14 days → red, then "1 day overdue" the day after.
2. **Flip sound.** Generate `flip.caf` (≤ 120 ms, 44.1 kHz mono): a mechanical toggle, i.e. a 3 ms
   broadband click with a 2.5 kHz resonance, then a second softer click 35 ms later, over a faint 180 Hz
   body thump, soft-limited at -3 dBFS. Play it on every flip through `AVAudioPlayer` in the ambient
   category (silent switch respected, never pauses music), preloaded with the board. A toggle "Flip
   sound" lives in the board's own `…` toolbar menu (stored in `AppGroup.defaults` key
   `flipboard.sound`, default on); haptics stay as they are. Record the synthesis parameters in a
   header comment where the player lives.
3. **Verify on video + ROADMAP.** On the iPhone 17 simulator, record: create "Shave" every 2 weeks
   (red, "Flip to start"), flip it (sound logged, green, "0 of 14 days"), then use a debug-only
   time-travel hook you remove before committing to show it turning red at 14 days. Mention the video path.
   Update the Flipboard paragraph in ROADMAP.md (start-red rule, sound).

## Verify
`scripts/test.sh` green; signed simulator and Mac builds. Report per COMMON.md.
