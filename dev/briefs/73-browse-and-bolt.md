# Brief 73: Browse's last row and swipe to delete; the bolt's coin spin (session `browse-and-bolt`, effort high)

Two small things in files nobody else touches this round. George, 2026-11-10, on 0.9.0 (20):

> The Browse tab has hidden button at the bottom again behind the home bar, and you also can't swipe left to delete
> Groups but I wish you could.

> The lightning bolt animation is very cute! But when I said "twirl and rise up a bit before slamming", I meant twirl
> on the Z axis, as in halfway through the twirl the bolt would technically be invisible or incredibly thin as the edge
> of the icon would be facing the user for a split second. The actual slam animation is almost perfect though, I love
> the slight warp and the sparks.

Read `dev/briefs/COMMON.md` (Round 16 block first), then `68-bolt-slam.md` and `61-lists-cleanup.md` (Browse).

## Items (one commit each, failing test first where there is logic)
1. **Browse's bottom on iPhone.** Scrolled to its end, Browse's last control sits behind the home indicator and the
   tab island: you cannot see or tap all of it. Find which control George means (scroll Browse to the bottom on the
   iPhone 17 simulator with demo data, with and without labels and filters), find which round's change brought it
   back (`git log -p` on `BrowseView.swift` and `MobileShell.swift`: build 6 solved this once with
   `contentMargins(.bottom, IslandMetrics.chromeHeight + 8)`), and fix it at the cause so every screen pushed inside
   Browse (a Group, a label, a filter, Shared Tasks) ends clear of the island too. Pin it with a UI test that
   scrolls Browse to the end and asserts the last control's frame is above the island's top and hittable, on the
   iPhone 17 and on a small phone (iPhone SE or the smallest simulator installed).
2. **Swipe left on a Group to delete it** in Browse (iPhone and iPad): a red Delete action, through the path the
   Group's own menu already uses (`askToDelete`, `GroupDeletion`: a Group with tasks asks first, an empty one goes at
   once). A full swipe must not skip the question for a Group with tasks. Shared Tasks, the forced Group, has no
   swipe. Labels and saved filters in Browse get the same swipe if their rows are list rows there (they delete
   without a question today from their menus; keep that). A deletion syncs to every device, as the user intends;
   never add a delete anywhere as a reset. UI test: swipe an empty Group away; swipe one with tasks and cancel.
3. **The bolt's twirl is a coin spin.** In `BoltSlamMotion` the `twirl` track turns the glyph in the plane of the
   screen. George means a spin about the vertical axis, like a coin on a table: half-way through each turn the bolt
   is edge-on, a hairline or nothing, then its other face comes round. Use a real 3D turn (`rotation3DEffect` about
   y with a little perspective, or the equivalent projection in `Warp`), one full turn during the hop so it lands
   face-on and unmirrored. Keep everything else exactly as it is: the crouch, the hop's height and timing, the hang,
   the slam, the squash and warp, the sparks, the 0.8 s length, the frame rate, Reduce Motion's blink, the rare gate
   (`BoltStrikeGate`), the Strike style. Update `BoltMotionTests` (the end state is still the resting glyph; a frame
   near the half turn is edge-on: its horizontal scale is near zero) and the Extras row's words if they describe the
   twirl. Record the frame strip as brief 68 did (`-boltStrikeDemo YES`), Mac and iPhone, and include the frames
   around the half turn.

## Ownership
`HITList/Views/Tabs/BrowseView.swift`, `HITList/Views/Groups/*`, `HITList/Views/Tabs/MobileShell.swift` only if the
bottom margin's cause is there (say so), `HITList/Support/BoltSlamMotion.swift`, the slam's lines in
`HITList/Support/SyncStatusViews.swift`, `HITList/Views/Delight/DelightSettingsSection.swift` (the row's words only),
`HITListTests/BoltMotionTests.swift`, `HITListTests/GroupsTests.swift`, a new `HITListUITests/BrowseUITests.swift`
(do not edit `HITListUITests.swift`: brief 72 edits it), your `dev/ROADMAP.md` row.
Not yours: `SidebarView` and the Mac's chrome (70: `SidebarSectionHeader` keeps its interface, call it as it is);
`Views/Flipboard/*` and the models (72); core's parser (71); `SyncState.swift`'s gate; `MobileTabBar`; `TaskRow`;
`CHANGELOG.md`, `WhatsNew.swift`, `scripts/`.

## Done
Screenshots: Browse scrolled to its end on both phone sizes, before and after; the swipe on a Group, with the
question for one that has tasks; the bolt's frame strip on the Mac and the iPhone with the edge-on frames marked.
All three suites green and the UI tests (`scripts/test.sh ui`) on a fresh simulator.
