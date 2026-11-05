# Brief 56: friends' first run, polished (branch `release-polish`, effort High)

Read `briefs/COMMON.md` (Round 11 block, both "Seeing the Mac app" and "Driving the iPhone app") and `briefs/HIG-NOTES.md`
(onboarding). Sessions 53–55 run at the same time. This is the last build before George invites friends; your job is
the first minutes of a friend's experience.

## Items (one commit each, failing test first where there is logic)
1. **A tip must never eat the first tap**: on a fresh install the "Find anything" tip (Browse) shows on the very first
   screen, and on iPhone a tip popover takes the first tap outside it to close itself, so a friend's first tap on "+"
   only closes the tip. Show the Browse tip only after the person has added their first task (a TipKit rule on a
   donated event) or on a later launch; check every other tip the same way (`Views/Tips/*`).
2. **Board cards' bottom line**: on the Mac/iPad board (270 pt columns) a card with a reminder bell, a checklist count,
   a label and a Group truncates to "5:38…" and "S". On the board only, let that line wrap to a second line (or drop the
   label first) so times and the Group stay readable; iPhone list rows keep one line and equal heights (George's rule).
   `TaskRow.swift` meta line via an environment value the board sets; `UpcomingBoard.swift`.
3. **Duo inner display on its side**: the system's vertical bar covers the board's last column (its horizontal scroll
   has no trailing safe-area margin). Fix in `UpcomingBoard.swift`; prove it with a geometry test.
4. **A friend's first run, recorded**: a new UI test (`HITListUITests`) on a fresh store: launch, add "Call mom tomorrow
   5pm p1", complete a task and see the Undo toast, open Browse, Settings, Account; screenshots at each step for George.
   Fix anything clumsy you find inside your ownership; report the rest.

## Ownership
`Views/Tips/*`, `Views/Upcoming/UpcomingBoard.swift` (+ card file), `TaskRow.swift` (meta line, board-only behaviour),
`HITListUITests/*`; tests new `ReleasePolishTests`; ROADMAP row "Friends' first run (brief 56)". Not yours:
`ProfileMenu.swift`, `BrowseView.swift` (53), `SyncStatusViews.swift` (54), `ClaudeSettingsSection.swift`, `HingeCreak*` (55).

## Done
All three suites green and `scripts/test.sh ui` green; the first-run screenshots; a Mac capture of a crowded board card.
