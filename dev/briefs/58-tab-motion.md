# Brief 58: the island moves (session `tab-motion`, effort high)

George, 2026-11-07, with a screen recording of Todoist's iPhone app:

> In Todoist, the screen changes/transitions between tabs are much cleaner and don't look as static, they seem to
> "load in" a little better. The home buttons at the bottom also have a nice moving highlight bubble to show what
> tab you're on, and there's a haptic bump when you tap a different tab. I've attached a screen recording of these
> interactions so you can understand the type of smoothness and cleanliness I'm talking about.

What the recording shows, frame by frame (read at 30 fps): the selected tab's pill is one view that slides from the
old tab to the new one over about 200 ms with a spring (it stretches a little mid-way and settles without a bounce);
the icon switches to its filled variant and the icon and label take the accent as the pill arrives; the outgoing
screen fades out while the incoming one fades in over roughly the same 200 ms, with no horizontal slide and no scale;
a light haptic on each change. Nothing happens when the current tab is tapped again (HITList pops to the root; keep).

Read `dev/briefs/COMMON.md`, then `HIG-NOTES.md` (motion and haptics). The island is `MobileTabBar` (a plain `HStack`
of buttons; the selected tab is tinted, there is no pill view yet), the shell is `MobileShell` (`stack(for: tab)`
swaps the tab's `NavigationStack` with no transition). The iPhone Duo's outer display stands the island upright
(`axis: .vertical`): the pill moves along that axis there. `TapHaptic` (`Support/Delight/TapHaptic.swift`) is the
app's haptic; `HITMotion` holds the motion tokens.

## Items (one commit each)
1. **The pill.** One capsule behind the selected tab, inset `IslandMetrics.pillInset`, moved with
   `matchedGeometryEffect` in a namespace owned by the island, animated with a new `HITMotion.tabPill` (a spring,
   response about 0.28 s, dampingFraction about 0.86, no visible bounce). Both axes. Reduce Motion: the pill jumps.
   `MobileChromeTests` pins the metrics it adds.
2. **The icon and label.** The filled symbol variant and the accent follow the selection with the same timing
   (`contentTransition(.symbolEffect(.replace))` or a crossfade, whichever reads cleaner); never a frame where two
   tabs look selected.
3. **The haptic.** A selection-changed haptic (`UISelectionFeedbackGenerator`, prepared when the island appears) on
   every tab change, none on a re-tap, through `TapHaptic` so any haptics switch in Extras applies.
4. **The screen crossfade.** In `MobileShell` the tab's stack gets `.id(tab)` and a transition of opacity plus a
   6-point rise (no slide: the Todoist frames show none), animated with `HITMotion.tabSwitch` (ease-in-out, 0.2 s).
   Popouts, the keyboard and the `place` reporting are untouched. Reduce Motion: opacity only, 0.15 s. Check that
   the incoming list's `onAppear` still sets `popouts.listContext` (the "+" must add to the list on screen).
5. **Verify with a recording.** `xcrun simctl io <udid> recordVideo` a few switches and look at the frames
   (`ffmpeg -i in.mp4 -vf "fps=30,tile=6x5" -frames:v 1 sheet.png`, then Read the PNG); fix anything that looks static
   or doubled.

## Ownership
`HITList/Views/Tabs/MobileTabBar.swift`, `HITList/Views/Tabs/MobileShell.swift`, `HITList/Support/Delight/TapHaptic.swift`,
the motion tokens file (`HITMotion`), `HITListTests/MobileChromeTests.swift`, a UI test beside `testTabsAndQuickAdd`.
Not yours: `ContentView`, popouts, anything in `Views/Inbox`, `Views/Flipboard`, `TaskListView`.

## Done
Frames of four tab changes in the report, showing the pill mid-travel and the crossfade; where the haptic fires,
in words (the simulator has no haptics). Three suites green.
