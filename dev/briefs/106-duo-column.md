# Brief 106: the iPhone Duo's outer display: the bar column and the lists (session `duo-column`, effort xhigh)

George, 2026-11-11, the evening 0.9.4 went out (his friend uses an iPhone Duo every day; the screenshot is
`round-21/george/duo-outer-flipboard.png` in the shared notes folder):

> My friend on his iPhone duo has noticed several screens that are poorly designed for his phone, including lots of
> overlapping text, poorly spaced buttons and symbols, and even overlapping menus (screenshot attached). It looks
> pretty bad indeed, but we haven't focused on the iPhone duo in a while either. Please take a pass in the simulator
> and both clean up the Duo version of the app as well as having the confidence to move/reorganize certain buttons
> or features to improve the user experience as you see fit (but don't feel the need to rerun rigorous tests for
> every version unless required).

Three sessions share the Duo tonight. **Yours is the outer display's shell and its lists**: the bar column, the
rows, Browse, the Flipboard's board. 107 (`duo-cards`) has what opens over a list there (quick add, the editor, the
pickers, Settings, sheets); 108 (`duo-inner`) has the inner display.

Read `dev/briefs/COMMON.md` (the Round 21 block first), `dev/SUPERVISOR.md` §7 (George's decisions), the Duo
briefs before this one (`45-iphone-duo.md`, `50-duo-hinge.md`, `63-duo-and-shell.md`), `dev/briefs/HIG-NOTES.md`
(the iPhone Duo section), and the code: `HITList/Views/Tabs/MobileShell.swift`, `MobileTabBar.swift`
(`IslandPlacement`, `IslandMetrics`), `ScreenMenu.swift`.

## The outer display, and how to see it
About 466 × 678 pt at 3x, compact width. Down its trailing edge runs the system's bar column (about 90 pt wide:
the trailing safe area) with the camera island, the clock and the battery ring; the system also draws an app's
toolbar items there, one under another. Our tab island stands upright at the foot of that column with the "+"
under it (briefs 50 and 63); the lists have the 376 pt left of it. An `iPhone Duo` simulator boots folded, showing
this display: no Device Hub needed. `xcrun simctl io <udid> screenshot --display=primary <file>` (without
`--display` it fails: the device has two). Brief 93's walk photographs every screen in a quarter of an hour:
`TEST_RUNNER_HITLIST_QA=1 xcodebuild test -project HITList.xcodeproj -scheme HITListUITests -destination
'platform=iOS Simulator,id=<UDID>' -derivedDataPath build.noindex/sim -only-testing:HITListUITests/QASweepUITests
-resultBundlePath build.noindex/qa.xcresult`, then `xcrun xcresulttool export attachments`;
`TEST_RUNNER_HITLIST_QA_LANDSCAPE=1` turns the device on its side. **The supervisor ran it on 0.9.4 before you
started: all 81 pictures are in `round-21/duo-walk-before/` in the shared notes folder. Look at them first.**

## What is wrong (the supervisor's reading of those pictures; verify each, find the rest)
1. **The column overflows: "overlapping menus".** Top to bottom it holds the system's status (to about 150 pt; to
   about 205 while a call or a timer widens the camera island, as in the friend's screenshot), then our toolbar
   items as the system stacks them (Back on a pushed screen, then the pill with the screen's control and the
   magnifying glass or the gear), then our island (about 250 pt) and the "+", anchored to the bottom. On a tab's
   first screen with nothing in the camera island they just clear each other. **On every pushed screen** (Browse,
   a Group, Completed: `4-BrowseAndSearch 002 Browse`, `… 005 A Group, Work`, `7-EmptyStates 006 empty Completed`)
   the pill's lower control is drawn on the island's top cell; with a call running the same happens on every
   first screen (the friend's Flipboard: the speaker is visible, the magnifying glass is under the island).
2. **Our content runs under the system's clock and battery: "overlapping text".** Upcoming's week strip
   (`1-Lists 005 list upcoming`: the days after Sunday are drawn under the battery ring) and Browse's row of saved
   filters (`4-BrowseAndSearch 002 Browse`: "Unsch…" under the ring) scroll sideways past the content's trailing
   edge into the column.
3. **A row's Group cut to one letter.** `1-Lists 001 list inbox`, "Frame the print": the meta line (repeat, date
   and time, sub-task count, a label) leaves the Group "Work" as "W". At XL (`8-DynamicType 002 type XL Inbox`)
   Groups read "Fin…", "…" and "Shared Ta…". The outer display has the rows' larger type (brief 63) on a list
   17 pt narrower than an iPhone 16's.
4. **The island at larger text sizes** (`8-DynamicType 001 type XL Today`): "Upcoming" and "Flipboard" are wider
   than the island and spill over its edges.
5. **With the keyboard up** (`2-QuickAddAndReview 001 Quick add, empty`, `6-FlipboardCards 001 Switch card,
   empty`) the keyboard covers the "+" and most of the island, and the island's top cell peeks out between the
   card and the keys.
6. Spacing in the column is uneven (clock to ring, ring to pill, pill to island, island to "+"), and the bolt
   scrolls away with the title while the pill stays.

## Item 1, first, as one commit (then message the supervisor its hash): the column
The supervisor's recommendation, to take or to beat with a reason: **the column is for the system and for getting
around: the clock and battery, Back, the tab island and the "+". A screen's own controls (the bolt, and the pill
with the screen's control and the magnifying glass or gear) leave the column and sit at the top of the content,
at the trailing end of the title's row, as on every other iPhone**, pinned there while the list scrolls under them
(glass, as the system's own floating bar items are). That needs no more height than today, puts the bolt and the
pill back together, and leaves the column with room to spare even during a call. Apple's guideline asks custom
bars to follow the system's vertical layout (`HIG-NOTES.md`); read what the SDK offers
(`toolbarVerticalEdge`, `toolbarVerticalBehavior`, `verticalBarEdge` in the SwiftUI and UIKit headers) before you
decide how, and say in the report where you left the guideline and why. George's licence tonight: "having the
confidence to move/reorganize certain buttons or features".
Whatever you build must pass all of these, each shown in a picture and pinned in `MobileChromeTests` by summing
the column's parts against the display's height:
- nothing in the column touches anything else: on a tab's first screen, on a pushed screen (Back and two
  controls), with the system's status 60 pt taller (a call; add a Debug launch argument that pads it, since the
  simulator has no call), at the largest text size, with the keyboard up;
- Back, the screen's control, the magnifying glass or gear, and the bolt are reachable on every screen, in the
  same place from screen to screen, and VoiceOver reaches them in a sensible order;
- the lists keep the height they have today (no new bar row above the title);
- the island's cells and the "+" keep brief 63's sizes unless you show why a change is better;
- on its side (466 pt tall) the island still falls back to the bottom (`IslandPlacement.sideMinimumWindowHeight`),
  and nothing overlaps there either;
- every other iPhone, the iPad and the Mac are unchanged (`ScreenMenu.swift` serves them all: show an iPhone 16
  before and after).
Then say in your message **where a companion could live on the outer display** (the upright "+",
`IslandAddButton`, has none today because the island stands on its head; the top of the island, in the room the
column now has, is the supervisor's guess) and how many points of clear room that place has above it. Session 104
draws it there once the supervisor forwards your answer; you only keep the room.

## Items after the column (one commit each; before and after pictures at real size)
2. **Nothing of ours under the system's items.** The week strip, Browse's saved filters and any other strip that
   scrolls sideways end at the content's trailing edge (clipped or faded there), on every screen.
3. **A row's meta line on a narrow list.** Decide what gives way and in what order so that a Group's name is
   never cut to a letter and nothing is drawn over anything else (the labels shorten or drop first; the Group
   keeps a readable minimum or moves to the line below: yours to judge, on the Duo and on an iPhone 16 at XL), and
   pin it in a test.
4. **The island at every text size**: a label never wider than its cell (cap the label's size, or drop to
   symbols past a size); the same for the bottom island on other iPhones if it has the fault.
5. **The keyboard**: while it is up the upright island is out of the way with the "+" (hidden, or moved), never
   peeking between a card and the keys. (The cards themselves are 107's.)
6. **The sweep.** Every list screen on the outer display at the default text size and at XL, upright and on its
   side: Inbox, Today, Upcoming, a Group, a label, a filter, Completed, Shared Tasks, Browse and its search
   results, the Flipboard (tiles, Switchboard headers, the empty board, a tile's menu, a drag), the empty states,
   the completion toast with Undo, a tip. A findings table (`106-duo-column/findings.md` in the shared notes
   folder: screen, what is wrong, fixed or left and why), worst first; fix what is wrong.
7. **Reorganise where the small display needs it**, with a sentence on why for each: George gave the licence, and
   his decisions in `dev/SUPERVISOR.md` §7 still hold (four tabs, Browse behind the magnifying glass, Settings
   behind Browse's gear, one view-options control per list, titles large and never buttons).

## Ownership
`HITList/Views/Tabs/*` (`MobileShell`, `MobileTabBar`, `ScreenMenu`, `BrowseView`), `Views/Duo/VerticalBar.swift`,
`Views/ListChrome.swift`, `Views/TaskListView.swift`, `Views/TaskRow.swift`, `Views/Inbox/InboxView.swift`,
`InboxZeroView.swift`, `Views/Upcoming/UpcomingView.swift`, `WeekStripView.swift`,
`Views/Calendar/CalendarEventRow.swift`, `Views/Shared/SharedTasksComponents.swift`, `SharedTasksEntry.swift`,
`Views/Flipboard/FlipboardView.swift`, `FlipboardGrid.swift`, `FlipSwitchTile.swift`,
`Views/Delight/CompletionToast.swift`, the list type roles in `Support/DesignSystem/HITTokens.swift`;
`HITListTests/MobileChromeTests.swift`, a new test file and a UI test file of your own. Not yours: `Views/Popouts/*`,
the Flipboard's cards, Settings, sheets (107); `ContentView.swift`, the rest of `Views/Duo/*`, `SidebarView.swift`,
the board (108: where a line of yours must change for the inner display, 108 changes it and says so); the
companions (`Views/Companions/*`, 104); `AppearanceSettingsSection.swift`, `ThemeCompanion.swift`, `scripts/`,
`dev/`, `CHANGELOG.md`, `WhatsNew.swift` (the supervisor).

## How to work
Your own simulators: `HITList-106` (an `iPhone Duo`) and, for the shared code, `HITList-106p` (an `iPhone 16`:
George's phone); your own derived data and side store. Build once, look, then iterate with `-only-testing`.
George: "don't feel the need to rerun rigorous tests for every version unless required": the three suites once at
the end, your own UI test file, and the walk on your Duo simulator before and after; the supervisor runs the whole
UI suite on the merged tree. Never push, merge, switch branches, run `scripts/release.sh` or answer a system dialog.

## Done
The column's hash and the companion's place sent early. The findings table. Before and after of every screen you
changed on the Duo's outer display (upright, on its side, XL, a pushed screen, the padded status, the keyboard up)
and of the same screens on an iPhone 16. The three suites green. The branch; changelog lines in plain words; what
you moved and why; what you could not see running; decisions George might reverse.
