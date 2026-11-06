# Brief 50: iPhone Duo, the HIG way, and a squeaky hinge (branch `duo-hinge`, effort xhigh)

Read `briefs/COMMON.md` (Round 11 block) and `briefs/HIG-NOTES.md` (the iPhone Duo section) first, then Apple's
page itself: https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo. Five sessions
run at the same time. Brief 45's report is in COMMON's Round 10 record.

George's words, 2026-11-05:

> Finally, if possible, add a responsive hinge noise to the iPhone Duo version, so that every time my friend opens or
> closes his Duo with HITList open, the hinges squeak/creak, which of course will only be funny if it can happen
> instantaneously when he goes to open the phone. Is that a thing we can do? Obviously a lower priority task, but
> it'd be fun.

## Items (one commit each, failing test first where there is logic)
1. **Vertical controls on the outer display** (HIG: "Follow the system's vertical layout for toolbars, tab bars, and
   navigation controls"; "don't override the default bar placement"): HITList's tab island and "+" oval are custom,
   so they stay at the bottom today. Where the system puts bars on the side (`traitCollection.verticalBarEdge`,
   SwiftUI `toolbarVerticalEdge`), put the island vertically along that edge (symbols with labels, same order top to
   bottom as left to right) with the "+" oval at its foot, and give the lists their room back; the inner display in
   portrait keeps the bottom island. Toolbar items keep a title and a symbol. Same state and selection across the
   switch.
2. **The inner display uses the board**: Upcoming on the Duo's inner display (regular width) shows the board, not the
   iPhone list (`UpcomingView.showsBoard` is iPad-idiom only today).
3. **Typing survives a fold**: an editor with unsaved typing keeps it when it moves between sheet (outer) and column
   (inner); today a new `TaskPopout` starts empty (round 10 open item).
4. **Reserved regions**: when the device is partly open, keep the editor column, the board and Flipboard's grid off
   the fold (`ReservedRegion`, division kind); Flipboard uses an even number of columns on the inner display.
5. **Squeaky hinge** (new `Support/Delight/HingeCreak*.swift`): while HITList is active and the hinge moves
   (`onHingeChange` / `UIHinge`), play a creak whose pitch and loudness follow the hinge's angular speed, starting
   within one or two frames of the first movement. Make the sound yourself (procedural synthesis in a pre-warmed
   `AVAudioEngine`: a resonant, slightly detuned friction squeak plus a low wooden creak, grains triggered by angle
   steps), so there is no third-party audio. Ambient audio session (honours the silent switch, mixes with music),
   no sound in the background, a gentle limit so it is never loud. Extras toggle "Squeaky hinge" (on), shown only on
   devices with a hinge: put the row in a new view of yours and add one line for it in `DelightSettingsSection`
   (session 49 changes that file's strings only). Measure the latency from the first hinge event to audio and say
   honestly whether the system delivers hinge changes fast enough (and whether it does at all while the outer display
   is showing HITList and the phone opens).
6. **Simulator**: use your own iPhone Duo simulator and Xcode's Device Hub poses/hinge slider if you can reach them;
   if not, drive the layout and the creak from tests and a Debug-only launch argument, and say what you could not see.

## Ownership
`Views/Duo/*`, `Views/Tabs/MobileShell.swift`, `MobileTabBar.swift`, `Views/ContentView.swift`,
`Views/Popouts/PopoutHost.swift` (placement and fold continuity), `Views/Upcoming/UpcomingView.swift` (`showsBoard`
only), `Views/Popouts/TaskPopout.swift` (fold continuity only; session 48 edits the Reminder pill region),
`Views/Flipboard/*` (column count on the inner display only), new `Support/Delight/HingeCreak*.swift`, one line in
`DelightSettingsSection.swift`; tests `DuoLayoutTests`, new `HingeCreakTests`; `project.yml` only to add files; ROADMAP
row "Duo vertical controls and squeaky hinge (brief 50)". Not yours: `BrowseView.swift` (51), `SidebarView.swift` (49).

## Done
All three suites green; iPhone Duo simulator screenshots of the outer display with the island on the side, the
inner display's board, an editor kept across a fold; the creak's latency numbers; the iPhone 17 unchanged.
