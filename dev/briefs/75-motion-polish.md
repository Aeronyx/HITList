# Brief 75: everything that moves, checked and put right (session `motion-polish`, effort xhigh)

George, 2026-11-10, starting 0.9.1:

> I want you to perform some checks on certain screen transitions/add certain animations where they would be best,
> such as better popouts, small UI interactions, etc. By "animations" in this instance I mostly mean anything that
> moves/should move within the app, as many things are clean and smooth right now but certainly not everything.

Read `dev/briefs/COMMON.md` (Round 17 block first), `dev/briefs/ROUND-17.md`, `dev/briefs/HIG-NOTES.md`, the motion
table in `HITList/Support/DesignSystem/README.md` and `HITMotion` in `HITTokens.swift` (the roles every animation in
the app must come from: quick, standard, emphasis, exit, the tab roles, their Reduce Motion stand-ins).

This is an audit first and a repair second. George has an eye for a single frame that pops; your job is to find
those frames before he does. The rule of taste: the app is calm and quick. Things arrive from where they were
summoned and leave to where they go; nothing bounces unless it is a toy (a switch, the bolt); nothing takes longer
than about a third of a second; two things that belong together move together on one curve; a state that changes
under the finger answers within a frame. At rest the app looks exactly as it does now: no layout, colour or type
changes ride along.

## Items
1. **The audit.** Walk every transition on the iPhone 17 simulator and in your Debug Mac app and record each one
   (`xcrun simctl io <udid> recordVideo`, then frames with `ffmpeg`, tiled into strips; on the Mac capture the
   window in a tight loop as brief 73 did for the bolt). A table in your report, one row per transition: what
   triggers it, what moves, measured duration, the `HITMotion` role or raw curve it uses today, and a verdict (fine,
   pops, jumps, lags, mismatched, too long). Cover at least:
   - the quick-add card opening, closing, saving, discarding (iPhone card, Mac floating, inline and board cards);
   - the task editor opening from a row and closing; its picker cards (date, time, Group, priority, labels,
     reminder, repeat) opening, moving beside a chip, closing; the keyboard moving aside for a card;
   - the completion (check, strike, slide away, toast in and out, Undo bringing the row back);
   - tab switches, a push into Browse and back, a tab returning to its first screen;
   - the Mac sidebar: selection moving between rows, hover, the Settings sections fading in and out, the sidebar
     hiding and showing;
   - the profile menu, What's New, the Discard question inside a card, tips arriving and leaving;
   - the Flipboard: a flip, a tile landing after it is added, the switch and Switchboard cards opening in place and
     closing, a board's count changing;
   - small controls under the finger or pointer: every design-system button style, chips, the segmented control,
     toggles, the checkbox, the "+" (press, release, disabled), highlights appearing in a title as you type.
2. **Repairs, worst first**, one commit per transition or family, each with before and after strips. Use the
   existing roles; add a role to `HITMotion` only when two or more places need the same new motion, and add it to the
   README's table. Typical repairs: a card that appears without coming from its button; a close that is slower
   than its open; content that jumps while its container animates; a list that reflows in one frame when a row
   leaves; a number that changes without `contentTransition`; a pressed state that waits for release.
3. **Small interactions where there are none and there should be.** Sparingly: a press that gives (a few percent
   of scale or a shade, back on release), a selection that glides instead of teleporting (the Mac sidebar's fill
   could follow the iPhone tab pill's example), a chip that settles when chosen. Each must be invisible to someone
   not looking for it.
4. **Reduce Motion and Reduce Effects**: every change has its calm stand-in, pinned by tests where the motion is
   described by a pure value (as `HITMotion`'s tests and `BoltMotionTests` do).
5. **Frame rate**: nothing you add may drop frames on the simulator's slow-animations-off run or peg the Mac's CPU
   while idle (no free-running timers; `TimelineView` only while something is on screen and moving).

## Ownership
`HITList/Support/DesignSystem/*` (motion roles and the control styles), `HITList/Views/Popouts/*` (cards, host,
pickers, editor), `HITList/Views/Tabs/MobileShell.swift`, `MobileTabBar.swift`, `HITList/Views/TaskRow.swift`,
`HITList/Views/Delight/Completion*.swift`, `HITList/Support/Delight/Completion*.swift`,
`HITList/Views/Account/ProfileMenu.swift`, `WhatsNewPopout.swift`, `HITList/Views/Tips/*`,
`HITList/Views/MacChrome/*`, `HITList/Views/Settings/Mac/MacSettingsPage.swift`, `SettingsRouter.swift`,
`HITList/Views/Flipboard/*`, `HITList/Views/Inbox/InboxProcess*.swift`, their tests, a UI test file of your own.
Not yours: `TaskListView.swift`, `InboxView.swift`, `Views/Upcoming/*` and `Views/Settings/GeneralSettingsSection.swift`
(77: if a list needs a line for a row to leave gracefully, give the exact line in your report and the supervisor
adds it after the merge); `SidebarView.swift`, `Views/Search/*` and `BrowseView.swift` (76 hangs a companion on
them: do not restructure them); `HITListApp.swift`, `project.yml`, anything under `HITListWidgets/` or
`Views/Companions/` (74, 76); the bolt's motions (George: "almost perfect"); `dev/ROADMAP.md`, `CHANGELOG.md`,
`WhatsNew.swift`.

## Done
The audit table. A before and after strip for every repair and every new interaction, iPhone and Mac. A short list
of what you judged fine and left alone, and what you would still change but did not dare without George. Proof the
app is pixel-identical at rest on Today, the Inbox, Upcoming, the Flipboard and an open editor (overlay before and
after). All three suites green and the UI suite on a fresh simulator.
