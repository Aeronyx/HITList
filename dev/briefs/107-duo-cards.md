# Brief 107: the iPhone Duo's outer display: cards, pickers, the editor, Settings (session `duo-cards`, effort xhigh)

George, 2026-11-11, the evening 0.9.4 went out (his friend uses an iPhone Duo every day; the screenshot is
`round-21/george/duo-outer-flipboard.png` in the shared notes folder):

> My friend on his iPhone duo has noticed several screens that are poorly designed for his phone, including lots of
> overlapping text, poorly spaced buttons and symbols, and even overlapping menus (screenshot attached). It looks
> pretty bad indeed, but we haven't focused on the iPhone duo in a while either. Please take a pass in the simulator
> and both clean up the Duo version of the app as well as having the confidence to move/reorganize certain buttons
> or features to improve the user experience as you see fit (but don't feel the need to rerun rigorous tests for
> every version unless required).

Three sessions share the Duo tonight. **Yours is everything that opens over a list on the outer display**: quick
add, the editor, every picker and card, Review Inbox, Settings and its pages, the sheets. 106 (`duo-column`) has
the shell there (the bar column, the rows, Browse, the Flipboard's board); 108 (`duo-inner`) has the inner display.

Read `dev/briefs/COMMON.md` (the Round 21 block first), `dev/SUPERVISOR.md` §7 (George's decisions), the Duo
briefs before this one (`45-iphone-duo.md`, `50-duo-hinge.md`, `63-duo-and-shell.md`), `dev/briefs/HIG-NOTES.md`
(the iPhone Duo section; modality and popovers), and the code: `HITList/Views/Popouts/PopoutHost.swift` (where a
card goes on a phone), `Views/Popouts/Pickers/PickerPlacement.swift` and `PickerPresenter.swift`.

## The outer display, and how to see it
About 466 × 678 pt at 3x, compact width: as wide as an iPhone, **174 pt shorter than George's iPhone 16**, and with
the keyboard up about 370 pt are left. Down its trailing edge runs the system's bar column (about 90 pt wide: the
trailing safe area) with the camera island, the clock and the battery ring; our content has the 376 pt left of
it. An `iPhone Duo` simulator boots folded, showing this display: no Device Hub needed.
`xcrun simctl io <udid> screenshot --display=primary <file>` (without `--display` it fails: the device has two).
Brief 93's walk photographs every screen in a quarter of an hour: `TEST_RUNNER_HITLIST_QA=1 xcodebuild test
-project HITList.xcodeproj -scheme HITListUITests -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath
build.noindex/sim -only-testing:HITListUITests/QASweepUITests -resultBundlePath build.noindex/qa.xcresult`, then
`xcrun xcresulttool export attachments`. **The supervisor ran it on 0.9.4 before you started: all 81 pictures are
in `round-21/duo-walk-before/` in the shared notes folder. Look at them first.**

## What is wrong (the supervisor's reading of those pictures; verify each, find the rest)
1. **The date picker does not fit.** In quick add (`2-QuickAddAndReview 003 Quick add, date card`) only its row of
   shortcuts and the month's name are on screen; the grid is below the display's bottom edge. In the editor
   (`3-Editor 002 Editor, date card`) the grid shows, the shortcuts above it are a third of their size and cut at
   the top, and "Add time" and "Repeat" under it are cut at the bottom. A date cannot be picked from the grid in
   quick add on this phone.
2. **The reminder picker is cut.** In the editor (`3-Editor 004 Editor, reminder card`) it starts left of the
   display's edge ("mind me from now", "minders arrive at the task's time…"); in quick add
   (`2-QuickAddAndReview 005 Quick add, reminder card`) its first row is under the card's chips.
3. **A card with a question in it grows off the top.** `6-FlipboardCards 003 Switch card, discard question`: the
   switch card's title is cut by the display's top edge once "Discard this switch?" is added under it, above the
   keyboard. Check quick add's and the editor's Discard the same way.
4. **Cards and the keyboard.** With the keyboard up the quick add card and the switch card sit hard against the
   keys with no margin, and the tab island's top cell peeks between card and keyboard (the island is 106's to
   hide; the card's margin and width are yours). With the keyboard down the quick add card sits low with a strip
   of the list under it.
5. **Review Inbox's calendar** (`2-QuickAddAndReview 012 Review Inbox, Pick a date`) covers the task it is about,
   title included.
6. **Settings at larger text** (`8-DynamicType 004 type XL Settings`): the page rows' second lines are cut
   ("Start screen, week, badge,…", "Alerts, default reminder, su…"); at the default size the pages look sound
   (`5-Settings …`), which the walk shows only from the top of each page.
7. Menus opening from the column (`2-QuickAddAndReview 009 Inbox view options`) and from a card's "+" cover what
   they belong to; fine where the system places them, wrong where we do.

## Items (one commit each; before and after pictures at real size, upright, keyboard up and down)
1. **Every picker fits the outer display, whole, wherever it opens** (quick add, the editor, Review Inbox, a
   switch's time, a Switchboard's reset time): the date card with its shortcuts, grid, Add time and Repeat; the
   reminder card; Repeat's menu and Custom…; priority, labels, Group. Nothing outside the content's area (not
   under the bar column, not past an edge), nothing under another card's controls, type at its role's size. A
   card too tall for the display gets a layout for short displays (denser rows, a section that scrolls inside
   the card, or two steps), not a clipped one. Pin the placement in tests against a 376 × 678 pt content area
   with and without the keyboard.
2. **Cards that grow** (a Discard question, a second line of chips, a long title) stay inside the display: they
   scroll inside, or the keyboard yields, never a title off the top.
3. **Quick add on the outer display**: where the card sits with the keyboard up and down, its margin from the
   keys and from the column, the chips row, the send button, a title of three lines.
4. **The editor** on a 678 pt display: its height and what shows without scrolling, its top bar beside the
   system's clock, the pills row, sub-tasks, the send button, a long title, every card it opens.
5. **The Flipboard's cards**: Add a Switch (every interval, a time, a Switchboard, Duplicate), the Switchboard
   card, the floating card of a switch.
6. **Review Inbox**: the three choices, the calendar beside (not over) the task, the toast.
7. **Settings**: the first screen and every page at the default text size and at XL, scrolled to the end, with
   Check iCloud…'s result, the Sync log, What's New, the quick add guide, the privacy page, the feedback card;
   second lines wrap rather than truncate where a row has the room to grow.
8. **The other sheets and cards**: Sharing… and an invitation, a Group's editor, a filter's editor, a new label,
   the profile's picture, a tip near the column, the Undo toast over a card.
9. **The sweep's table** (`107-duo-cards/findings.md` in the shared notes folder: screen, what is wrong, fixed or
   left and why), worst first, and **reorganise where the small display needs it**, with a sentence on why for
   each: George gave the licence ("having the confidence to move/reorganize certain buttons or features"), and
   his decisions in `dev/SUPERVISOR.md` §7 still hold (adding or editing a switch is a small card, never a
   sheet; a Discard question sits inside the card it concerns; tips never push the layout).

## Ownership
`HITList/Views/Popouts/*` with `Editor/*` and `Pickers/*` (in `PopoutHost.swift` the phone's placement only: the
inner display's column placement, `.duo`, is 108's), `Views/Flipboard/SwitchCard.swift`, `FloatingSwitchCard.swift`,
`SwitchboardCard.swift`, `SwitchControls.swift`, `SwitchTimeChip.swift`, `Views/Inbox/InboxProcessView.swift`,
`InboxPicker.swift`, `Views/SettingsView.swift`, `Views/Settings/*` (not `AppearanceSettingsSection.swift` or
`ThemeCompanion.swift`: the supervisor's tonight; not `Settings/Mac/*`), `Views/Delight/DelightSettingsSection.swift`,
`Views/Calendar/CalendarSettingsRows.swift`, `Views/Help/*`, `Views/Shared/SharingSheet.swift`, `SharedInvite.swift`,
`SharedTaskPopout.swift`, `Views/ProjectEditorView.swift`, `FilterEditorView.swift`, `Views/Tips/*`, the design
system's sheet, page, card and picker components (not `HITTokens.swift`: 106's list roles); test files and a UI
test file of your own. Not yours: `Views/Tabs/*`, the rows, the lists, the Flipboard's board and tiles (106);
`ContentView.swift`, `Views/Duo/*`, `SidebarView.swift`, the board (108); the companions; `scripts/`, `dev/`,
`CHANGELOG.md`, `WhatsNew.swift`.

## How to work
Your own simulators: `HITList-107` (an `iPhone Duo`) and, for the shared code, `HITList-107p` (an `iPhone 16`:
George's phone, where every one of these cards must look as it does today or better: show it); your own derived
data and side store. Build once, look, then iterate with `-only-testing`. George: "don't feel the need to rerun
rigorous tests for every version unless required": the three suites once at the end, your own UI test file, and
the walk on your Duo simulator before and after; the supervisor runs the whole UI suite on the merged tree. Never
push, merge, switch branches, run `scripts/release.sh` or answer a system dialog.

## Done
The findings table. Before and after of every card, picker and page you changed on the Duo's outer display
(keyboard up and down, XL where it matters) and of the same on an iPhone 16. The three suites green. The branch;
changelog lines in plain words; what you moved and why; what you could not see running; decisions George might
reverse.
