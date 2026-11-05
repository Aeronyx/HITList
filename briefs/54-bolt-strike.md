# Brief 54: a lightning-strike flash on a good sync, bolt 15% larger (branch `bolt-strike`, effort High)

Read `briefs/COMMON.md` (Round 11 block) and `briefs/HIG-NOTES.md` (motion: no gratuitous effects). Sessions 53, 55, 56
run at the same time. Last build before friends join.

George's words, 2026-11-05:

> I love that the lightning bolt sync icon is a bit flickery by nature because it feels like actual lightning. Perhaps
> we could even lean into it with a clean, short, unobtrusive lightning strike twirl/flash animation when a sync is
> successful, but it should be fast, clean, high framerate, and draw little attention to itself. Also, please make
> the icon slightly larger (say around 15% or so) on both desktop and mobile.

## Items (one commit each, failing test first where there is logic)
1. **Size**: `SyncBolt` about 15% larger on iPhone, iPad and Mac (today 11 pt: about 12.5–13 pt), keeping its
   alignment with the toolbar controls and the hit area; check the iPhone top bar and the Mac toolbar in captures.
2. **The strike**: when a CloudKit import or export finishes successfully (`CloudSyncMonitor.lastChangeAt` advancing,
   the same signal `SyncConfirmation` uses for the dot's pulse), the bolt plays one strike: ≤ 300 ms, e.g. a quick
   brightness flash with a small twirl (a few degrees) and a hair of scale (≤ 1.12), easing out to rest. GPU-cheap,
   smooth at 120 Hz (keyframe/phase animator or a short `TimelineView`, no per-frame allocations), bursts merged (no more
   than one strike every few seconds), nothing on launch's first import storm, none while the app is in the
   background, none under Reduce Motion (then at most a 150 ms opacity blink). The flickery idle look stays as it is.
3. **Test it**: the trigger rules (merge, cooldown, reduce motion) in unit tests; record the strike on the simulator
   (`xcrun simctl io recordVideo`) and pull frames to check timing and smoothness; capture the Mac toolbar at rest.

## Ownership
`Support/SyncStatusViews.swift` (`SyncBolt`, `SyncIndicatorDot` if shared), `Services/SyncState.swift`
(`SyncConfirmation`), `Views/Tabs/ScreenMenu.swift` (only if the larger bolt needs a layout tweak); tests
`SyncStateTests`, `MobileChromeTests`; ROADMAP row "Bolt strike and size (brief 54)". Not yours: `CloudSyncMonitor.swift`
(read its signals), `ProfileMenu.swift` (53).

## Done
All three suites green; frames of the strike from a simulator recording; Mac and iPhone captures of the larger bolt.
