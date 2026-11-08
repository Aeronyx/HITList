# Brief 68: a second bolt style, the slam (session `bolt-slam`, effort xhigh)

George, 2026-11-08, on 0.8.1:

> Can the bolt sync animation be a bit cooler? Have it twirl and strike, but not longer than a second; it should only
> twirl once or twice, bounce up slightly, and slam into the ground, perhaps warping a bit and releasing a tiny buzz of
> sparks/electricity, all within a second. It must be high framerate and shouldn't draw too much attention to itself as
> users will see it constantly. Keep the current lightning bolt as well and have this be a toggleble setting. (Use a
> separate agent for this with whatever effort is best for icon animation).

Read `dev/briefs/COMMON.md`, `dev/briefs/ROUND-15.md`, `54-bolt-strike.md`, and `HITList/Support/SyncStatusViews.swift`
(`SyncBolt`, `BoltStrikeMotion`: a quick double flash with a twirl of a few degrees, 280 ms) with
`HITList/Services/SyncState.swift` (`BoltStrikeGate`). The gate is George's rule from 0.7.1 and stays exactly as it is:
the bolt plays only as a "you're good to go" (the first good sync after launch, after a minute or more away, after a
minute or more of sync trouble), never on ordinary syncs, never in the background, a blink under Reduce Motion. This
brief changes what plays, not when.

## Items (one commit each, failing test first where there is logic)
1. **The slam.** A new motion (`BoltSlamMotion`, its own file beside `BoltStrikeMotion`) in the same glyph and place:
   the bolt twirls once or twice about its centre, lifts a few points, then slams down past its rest position and
   settles, squashing and warping slightly on impact, and lets off a tiny buzz of sparks or a crackle of electricity
   at its foot that fades almost at once. All of it within one second (aim for 0.7–0.9 s), most of the travel fast,
   the settle soft. Small: it must read as a flourish of a 13 pt toolbar icon, never a show. Draw the sparks in a
   `Canvas` (or a few shapes) driven by one `TimelineView(.animation)` or `keyframeAnimator` so it runs at the
   display's rate (120 Hz on ProMotion iPhones since 0.7.1's `CADisableMinimumFrameDurationOnPhone`, the Mac's refresh
   rate); keep the sparks inside a small radius so the toolbar does not clip them oddly. The tint and states follow the
   bolt's as today (filled when synced).
2. **The setting.** Settings → Extras gets one row, "Bolt" (or "Sync bolt"), choosing Strike (today's) or Slam, in the
   design system's own picker look, on iPhone and the Mac's Settings page. Store it in `AppGroup.defaults` under a key
   of your own, read where the bolt plays. Default: Slam (the cooler one George asked for); report it as a decision he
   may reverse. Reduce Motion still gets the blink for both.
3. **Prove the frames.** Record the slam frame by frame on the Mac (the Debug demo, `-boltStrikeDemo YES`, re-arms the
   gate before each fake sync) and on the iPhone 17 simulator: a strip of frames at 1/60 s steps with timestamps, plus
   the motion's keyframe table in the report (rotation, offset, scale per time). Check it stays under a second, never
   leaves a mark when it ends, and looks right at 1x and 2x. Pin the duration and the end state in a test, as
   `testTheStrikeIsShortAndSmall` does for the strike.

## Ownership
`HITList/Support/SyncStatusViews.swift` (`SyncBolt` and its motions), new `HITList/Support/BoltSlamMotion.swift` (or under
`Support/Delight/`), `HITList/Views/Delight/DelightSettingsSection.swift` (the one row), the Mac Settings page's Extras
section only if it does not reuse that view, `HITListTests/SyncStateTests.swift` (bolt tests) or a new
`HITListTests/BoltMotionTests.swift`, your `dev/ROADMAP.md` row.
Not yours: `SyncState.swift`'s gate (unchanged), `HITTokens` (67), `ScreenMenu` (66; the bolt's toolbar item stays as
it is).

## Done
The frame strips for both styles on the Mac and the iPhone, the keyframe table, Settings → Extras with the new row on
both platforms. All three suites green.
