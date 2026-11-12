# Brief 108: the iPhone Duo's inner display (session `duo-inner`, effort xhigh)

George, 2026-11-11, the evening 0.9.4 went out (his friend uses an iPhone Duo every day; the screenshot, of the
outer display, is `round-21/george/duo-outer-flipboard.png` in the shared notes folder):

> My friend on his iPhone duo has noticed several screens that are poorly designed for his phone, including lots of
> overlapping text, poorly spaced buttons and symbols, and even overlapping menus (screenshot attached). It looks
> pretty bad indeed, but we haven't focused on the iPhone duo in a while either. Please take a pass in the simulator
> and both clean up the Duo version of the app as well as having the confidence to move/reorganize certain buttons
> or features to improve the user experience as you see fit (but don't feel the need to rerun rigorous tests for
> every version unless required).

Three sessions share the Duo tonight. **Yours is the inner display**, the one the phone opens onto: about
669 × 951 pt upright, regular width, where HITList shows the sidebar layout with the editor in a column beside
the list (`AppShell.duo`, `DuoSplit`; briefs 45 and 50), Upcoming's board and the Flipboard's even grid. 106
(`duo-column`) and 107 (`duo-cards`) have the outer display.

**Nobody has looked at the inner display since round 14, a week and seven releases ago.** Since then Settings
became a first screen with pages, companions arrived (on the "+" and, on the Mac, on the sidebar's search field),
the Flipboard got Switchboards, cards, drag and Duplicate, the repeat picker and Custom…, the quick add guide,
Check iCloud…, time zones, the bolt's new states. Rounds 19 and 20 list it under "never seen running". Expect to
find more than the outer display's sessions will.

Read `dev/briefs/COMMON.md` (the Round 21 block first; the Round 10, 11 and 14 records for what the Duo sessions
before you learned), `dev/SUPERVISOR.md` §7 (George's decisions), `45-iphone-duo.md`, `50-duo-hinge.md`,
`63-duo-and-shell.md`, `dev/briefs/HIG-NOTES.md` (the iPhone Duo section), and the code: `Views/ContentView.swift`,
`Views/Duo/*`, `Views/SidebarView.swift`, `Views/Popouts/PopoutHost.swift` (the `.duo` column).

## Item 1: get there, and write down how (first; an hour at most before you fall back)
An `iPhone Duo` simulator boots folded, on the outer display. The fold is Device Hub's
(`/Applications/Xcode.app/Contents/Applications/DeviceHub.app`: Xcode 27 has no Simulator app): brief 50 opened the
phone by pressing Device Hub's pose buttons through Accessibility (this Mac's shells have the permission; that
session left no script). Find the buttons again, open your own simulator (only yours: 106 and 107 keep theirs
folded and never touch Device Hub), and **save what worked as a script and a few lines of notes in the shared
notes folder (`108-duo-inner/unfold.sh`, `README.md`)** for every round after this one. Screenshots of the inner
display: `xcrun simctl io <udid> enumerate` lists the device's two displays; `screenshot --display=<id>` takes one
(`primary` is the outer). If the real fold cannot be reached in an hour, work on the stand-in and say so in every
picture's name: `-duoStandIn YES` on an iPad mini simulator (744 × 1133 pt) is the Duo's shell on a display a
little larger than the inner one, `-duoCrease 360` draws the crease, `-duoFoldDemo 8` swaps folded and unfolded
every 8 seconds (`Views/Duo/DuoDebug.swift`).

## Item 2: look at everything, then write the list (`108-duo-inner/findings.md`, worst first)
Brief 93's walk runs on whatever it is given ("an iPhone's four tabs, or the iPad's and the Duo's sidebar"):
`TEST_RUNNER_HITLIST_QA=1 xcodebuild test -project HITList.xcodeproj -scheme HITListUITests -destination
'platform=iOS Simulator,id=<UDID>' -derivedDataPath build.noindex/sim -only-testing:HITListUITests/QASweepUITests
-resultBundlePath build.noindex/qa.xcresult`, then `xcrun xcresulttool export attachments`
(`TEST_RUNNER_HITLIST_QA_LANDSCAPE=1` for its side). Run it unfolded, upright and on its side, and then look
by hand at what it does not reach. Every screen, as George's friend would meet it:
- the sidebar (profile, search, Inbox to Flipboard, Groups, Filters, Labels), every list, Upcoming's board,
  the Flipboard's grid and cards, Browse's equivalents, search;
- the editor column beside the list (open, empty, a long title, every card it opens, sub-tasks, the keyboard),
  quick add and its pickers, Review Inbox;
- Settings (a sheet? a page? at what size?) and every page; the sheets (Sharing…, What's New, the guide);
- **on its side** (951 × 669): the system moves its bars to the trailing column there, as on the outer display
  (the Round 11 record's open item: "on the Duo's inner display on its side the system bar overlaps the board's
  last column");
- **half open** (the crease: `ReservedRegion`, division): nothing we draw sits on the fold;
- **folding and unfolding** with a list scrolled, a card open with text in it, the editor open with typing in
  it, Settings open, the keyboard up: the same place, the same text, nothing lost, nothing left behind;
- the companion: on the inner display it should be where it is on an iPad (on the "+"), seated, not clipped;
- the larger text sizes (XL at least).
For each: nothing on top of anything else, nothing cut, nothing under the system's clock or camera, one size of
type per role, margins that match the rest of the app, controls where a hand holding an open Duo reaches them.

## Item 3 onward (one commit each; before and after pictures at real size)
Fix what the list holds, worst first. Then **reorganise where this display needs it**, with a sentence on why for
each: George gave the licence ("having the confidence to move/reorganize certain buttons or features to improve
the user experience as you see fit"), and his decisions in `dev/SUPERVISOR.md` §7 still hold (the same
functionality and state on both displays; no detail column on the Mac or iPad, the editor column is the Duo's
alone; the Flipboard is a calm status check; settings open as a sheet on iPhone). A display this size held like a
book is not a small iPad: say where an iPad's layout is wrong for it.
Pin what you decide in `DuoLayoutTests`.

## Ownership
`HITList/Views/ContentView.swift`, `Views/Duo/*` (not `VerticalBar.swift`: 106's), `Views/SidebarView.swift`,
`Views/Search/*`, `Views/Upcoming/UpcomingBoard.swift`, the inner display's column placement in
`Views/Popouts/PopoutHost.swift` (`.duo`), `HITListTests/DuoLayoutTests.swift`, test files and a UI test file of
your own. The files of 106 (`Views/Tabs/*`, the rows and lists, the Flipboard's board) and 107 (`Views/Popouts/*`,
the cards, Settings, the sheets) are theirs: where the inner display needs a line changed in one of them, change
only that line, behind the shell or the size it applies to so that the outer display and every other iPhone are
untouched, and list every such line in your report (the supervisor merges all three). Not yours at all: the
companions' files, `AppearanceSettingsSection.swift`, `ThemeCompanion.swift`, `Settings/Mac/*`, `Views/MacChrome/*`,
`scripts/`, `dev/`, `CHANGELOG.md`, `WhatsNew.swift`.

## How to work
Your own simulators: `HITList-108` (an `iPhone Duo`), `HITList-108m` (an iPad mini, the stand-in) and, where
shared code changes, an `iPhone 16` and an iPad (the sidebar layout is theirs too: show them unchanged); your own
derived data and side store. Build once, look, then iterate with `-only-testing`. George: "don't feel the need to
rerun rigorous tests for every version unless required": the three suites once at the end, your own UI test file,
and the walk before and after; the supervisor runs the whole UI suite on the merged tree. Quit Device Hub when
you finish. Never push, merge, switch branches, run `scripts/release.sh` or answer a system dialog.

## Done
How to unfold the simulator, as a script and notes. The findings table. Before and after of every screen you
changed on the inner display (upright, on its side, half open), and the fold kept across each open thing. Which
pictures are the real display and which the stand-in. The three suites green. The branch; changelog lines in
plain words; what you moved and why; what you could not see running; decisions George might reverse.
