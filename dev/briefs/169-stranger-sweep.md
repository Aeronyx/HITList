# 169: every screen as a stranger sees it, in pictures, with what is wrong (a review; no code)

George, 2026-11-18: "Please take more time to prepare a build that is truly worthy of both the new sync engine and
to be sent to a wider group of friends." People who have never met him will open this build. Round 33's own run
showed what agents' proofs miss: tasks drawn as rings with no words, an hour's name half under a marker, found
only when the supervisor looked at the pictures. **Your work is to look**: every screen, every state a new person
meets in their first week, on an iPhone, an iPad and the Mac, as pictures, read one by one.

**You change no file in the repository** except one: a UI test file of your own,
`HITListUITests/StrangerSweepUITests.swift`, that walks the app and saves the pictures (on demand: skipped unless
`HITLIST_SWEEP=1`; `HITLIST_SHOTS_DIR` as `SyncEngineStatusUITests` reads it, and **the variable must be in
`xcodebuild`'s environment as `TEST_RUNNER_HITLIST_SHOTS_DIR=…` before the command, not after it**). Existing
tours help: `ScreenTourUITests`, `QASweepUITests`. Three traps from round 33: an `accessibilityIdentifier` on a
container lands on each of its parts; `app.swipeDown()` starts where XCUITest likes, so drag by
`app.coordinate(withNormalizedOffset:)`; two simulators typing at once share the Mac's keyboard, so run one UI
test process at a time.

What to walk, with the demo week (`-seedDemoData YES`) and then with an empty store (a new person's):
1. **First launch**: every question and screen until the first task is added; then the same with each question
   answered the other way.
2. **Each tab and list** (Inbox, Today, Upcoming as list and as Week, Flipboard, Browse, a Group, a label, a
   filter, search with and without results), at rest and scrolled to the end, with the floating + and the
   companion in view.
3. **Every card and picker**: quick add empty, typed, with every chip set, with its row scrolled; a task's card
   with everything filled; each picker open; the delete questions; Review Inbox; a switch's and a board's card.
4. **Settings**, every page and sub-page top to bottom; the iCloud page in each state the app can show without
   iCloud (`-disableCloudKit YES`, and the engine's states through `SyncEngineStatusUITests`' launch arguments).
5. **States**: an empty Inbox, an empty Today, nothing overdue, everything overdue, a task with a very long title
   and a very long description, forty tasks on one day, three tasks at one time in Week, a Group with a long
   name, the largest and the smallest Dynamic Type size, Reduce Motion, another theme or two.
6. **The Mac** (`scripts/window-shot.sh`, `window-drive.sh`; the supervisor keeps the display awake): the main
   window at its smallest and at a large size, the sidebar, Upcoming's board and Week, quick add, a task's card,
   Settings' every section. **The iPad** (a simulator of your own): the same lists at full width and in a narrow
   split.

**A finding** is numbered, with a severity (**A** a person cannot do something, loses what they typed, or is told
something untrue; **B** it looks broken, cut, overlapped, misaligned, or reads badly; **C** polish), the picture's
file name, what is wrong in one line as the person would say it, and where in the code it comes from if you can
see it in a few minutes (`path:line`; do not dig). Text within 12 pt of a card's or the screen's edge, 8 pt beside
a control or 6 pt between unlike things is a finding (George: "lazy and unprofessional"). So is anything truncated
at the default size on an iPhone 16-sized screen, a control that looks disabled and is not (or the reverse), a
word from inside the project, two names for one thing, and a screen with nothing to say what it is for. No praise,
no restating what works.

Your report: the findings in order of severity; the count of pictures and their folder
(`…/round-34/169/iphone/`, `ipad/`, `mac/`, named by screen and state); what you could not reach and why. Take the
time it needs: a sweep that stops at the first forty pictures is not one.
