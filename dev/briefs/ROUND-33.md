# Round 33 (2026-11-18, afternoon): 0.9.15, the release that goes to strangers

0.9.14 was prepared and not released. George had deployed the engine's Production schema and wrote on the 18th:
"Several external testers are now also using HITList on 0.9.13, and as it takes a while to release a new build for
them, I want to ensure this next one is incredibly solid." What he had seen: Settings pages that are "not very
user-friendly (such as the Calendar page)", "tooltips [that] are really hard to read/need to be more concise/need to
have better UI logic so they stop looking broken/changing aspect ratio", an iPhone app that is "a bit slow to respond
now (taps take 1 second or so to register …)". What he asked for: a Week layout in Upcoming (with a reference
picture), quick add's chips as "a horizontally scrolling bar, not one that wraps", "definitely keep tasks on the
device after sign-out if possible", "remove any identifying information from the repository", an explanation of how
Todoist's sync differs from ours (answered in chat), and of the engine: "I'd even rather the update just
automatically move their tasks after we've confirmed the new engine is working. The less technical stuff my friends
have to deal with, the better." He offered his phone for the round's testing and asked for a lot in the two hours
before his weekly usage limit reset.

## How it ran

Seven Opus 5.5 agents started at once with the Agent tool, each in its own worktree, briefs committed first
(161 to 167), a report due in 85 minutes and "commit each item the moment it is whole" because the limit could have
stopped them all. Every merge was clean except the generated project file (regenerated). The supervisor merged each
as it reported, made the changes the agents found outside their own files, and ran the suites on the merged tree.
The version is 0.9.15; 0.9.14's notes are folded into it, as 0.9.10's were into 0.9.11.

| Brief | What | Result |
|---|---|---|
| 161 `upcoming-week` | Upcoming's Week layout | Built, items 1 to 5: a Layout button (List or Board, and Week), `UpcomingWeekModel` from `UpcomingSchedule` (the list's own source: a hosted test holds each day's items equal to the list's), three days on iPhone and seven on iPad and Mac, the all-day band, the hours, the present-time line (its own `TimelineView`), chips that open and complete as rows do, an Overdue list. Not built: a tap on an empty hour, dragging, calendar events |
| 162 `chips-and-tips` | Quick add's chips in one scrolling row; the tips | `QuickAddChipRow`: one row, 16 pt fades only where more waits, a changed chip scrolls into view, the card's height fixed. Tips: one width per platform, laid out once, eight tips rewritten shorter, contrast computed for every theme (a test), never over a popout, gone once their subject is used |
| 163 `settings-clarity` | Settings a friend can read | The Calendar page rebuilt round one switch and an Access row; shorter titles and footers on General, Reminders, Extras, iCloud & data, Backups, Claude. No preference, default, action or the seven-tap row changed |
| 164 `iphone-response` | The iPhone's taps | A probe (`ResponseProbe`, Debug) and an on-demand UI test (`PhoneResponseUITests`, `HITLIST_PERF=1`). Finding: taps are recognised at once (the main thread starts 0 to 38 ms after the finger lifts); the time is main-thread work drawing the answer. One fix: `PopoutController` wrote observable state on every tab switch and list appearance with nothing open (warm tab switches, Debug simulator: 742 to 503 ms of main-thread work). **The phone could be installed on and launched but not driven** (UI automation is switched off on it; `xctrace` saw it offline), so nothing was measured on it |
| 165 `sign-out-keeps-tasks` | On the engine a sign-out removes nothing | `signOut()`, `rejoin()`, `checkRejoin()` in the brain; invariant I11; 1,000 histories of each of nine fault sets with no failure; `all` fails in about a quarter of its histories before and after (written in `SYNC-ENGINE.md` section 13) |
| 166 `repository-scrub` | No identifying strings in the files | The feedback address is a build setting from the untracked `Config/Local.xcconfig`; surname, home paths, a simulator id and a personal-looking address in a fixture replaced; found the App Store Connect key's ids in `release.sh` and the handbook (the supervisor moved them to the same untracked file) |
| 167 `automatic-move` | The move made by the app itself, off | `SyncEngineAutoMove`: rules R1 to R4, twenty tests, the constant false and pinned; found that set-aside stores were pruned to the newest two (now kept thirty days) and that a cancelled "download" move back still set the store aside (fixed) |

## The supervisor's own changes

- The App Store Connect key's ids out of `scripts/release.sh` and `dev/SUPERVISOR.md`: read from the environment or
  `Config/Local.xcconfig`, with a check beside the feedback address's.
- `ModelContainerFactory.trashStore` keeps a copy thirty days whatever came after it (167's finding 1).
- `CloudSyncMonitor.statusWords` carries the automatic move's line when it is on (167's diff; nil while off).
- On the engine a sign-out no longer clears reminders; the banner and Settings → Account say the tasks stay on this
  device (165's findings outside its files).
- The theme swatches' companion seat is worked out once per character and seat (164's finding 1: about 0.8 s of
  main thread each time Settings → Appearance drew, Debug simulator).
- Checked George's deploy: the engine's container's Production schema holds exactly the schema file's 61 fields.
- `dev/SYNC-ENGINE.md` sections 10 to 14 rewritten for the sign-out and stage 6.

## What the merged tree's own run found (the supervisor, after the merges)

- **The Week layout's hours**: agent 161 reported that its test's swipes "did not scroll the grid". A test of the
  supervisor's (`testTheHoursScrollAndASidewaysSwipeMovesTheDays`: a drag, a flick and a sideways swipe by screen
  coordinates) showed the grid does scroll, and that XCUITest's own `app.swipeDown()` begins above it on that
  screen. The sideways swipe was all the same moved from a SwiftUI `DragGesture` on the view that holds the scroll
  view to a UIKit pan that begins only for a sideways move (`SidewaysPan`), so nothing can take the hours'
  scrolling on any iOS; the test holds both.
- **Tasks at one time on an iPhone** were drawn as rings with no words, and three of them ran out of their column:
  a chip narrower than 72 pt now drops its ring and keeps its words ("W…", "C…", "D…" at three abreast).
- **An hour's name half under the present time**: the name is covered whole while the time stands within about a
  third of an hour of it.
- The picture test now brings nine o'clock into view with a finger in the grid, and the Overdue list has its
  picture.
- `SweepPolishUITests.testTheSummaryTimeIsOurTimeField` failed in the full run (a second simulator was typing at
  the same time) and passed alone.

## Left open, on purpose or for want of proof

- **The iPhone's slowness is not explained on George's phone.** What runs only with the real store and iCloud on
  (reminders rescheduled 2 s after each save; the mirror's export; `SyncAudit.compare`, which is `@MainActor`) ran
  in none of 164's measurements. To measure it the phone needs Settings → Developer → Enable UI Automation (his to
  switch on) or a session with Instruments. Every tab switch still rebuilds its whole screen (`MobileShell` builds
  only the tab on show): keeping tabs alive is a structural change, not made.
- The Flipboard never lets XCUITest see the app idle (164's finding 4, 162 saw the same): something animates
  without end there, likely the overdue light's `TimelineView`. Not established whether it is new.
- 161: quick add from an empty hour, dragging a chip and calendar events in the Week layout are not built; the
  Mac's Week layout was seen only as a picture drawn offscreen by a hosted test.
- 162: no Mac or iPad pictures of the tips (the agents' Debug Mac apps opened no window); one Mac hover text longer
  than 60 characters is listed in its report and unchanged.
- 163: `AccessibilityAuditUITests.testSettingsPages` has two findings on rows it did not change, not shown to
  predate it; Reminders' "Default reminder" subtitle still wraps.
- 165: a purge question still open is replaced by a sign-out; the engine's status line while signed out is the
  mirror's short one.
- 167: whether a Mac left open for weeks should be told to reopen; the hand move does not check sign-in.
- The history: every commit's author line carries George's name and address, and nine commits' content the
  address. A rewrite or a private repository is his decision.
- The first name "George" stays in `dev/` and the code's comments (about 1,450 places): asked of him.

## Proof

On the merged tree: core 1,092 tests, the Mac 2,330, the iPhone 2,291, no failures. The whole UI suite once (172
tests: 109 passed, 62 on demand, the one above that passed alone), then `UpcomingWeekUITests` (now six) again on
the final tree. Archive and export of both platforms pass every packaging check, and the exported apps carry the
feedback address. CI green on the merge. The simulation: 1,000 histories of each of nine fault sets, no failure
(agent 165's run). Not proven: anything on George's phone; the Mac's Week layout and the tips on a Mac or an iPad
by eye; the automatic move against iCloud (it is off).
