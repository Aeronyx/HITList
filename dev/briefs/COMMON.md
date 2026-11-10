# HITList: facts every delegated session must read first

HITList ("Human-in-the-List") is George's personal Todoist-style task app: SwiftUI multiplatform
(iOS 18+, macOS 15+), SwiftData with CloudKit private database `iCloud.com.trammells.hitlist`,
pure-Swift package `HITListCore` (filter query language, quick-add parser, autocomplete, recurrence,
snapshot JSON; 43 XCTest tests) and app test bundle `HITListTests` (in-memory container, hosted in the
app, runs on iOS simulator and macOS; 21 tests). Build 1 (0.1.0) is on TestFlight on George's iPhone 16
and Mac. George uses it daily as their primary task app and will later share it with friends.
`dev/ROADMAP.md` is the plan. Dark slate theme only, never light mode (`HITList/Support/Theme.swift`:
`Theme.background/surface/elevated/separator/accent/secondaryText`, `slateList()`, `slateRow()`,
`slateSheet()`; `HITList/Support/Formatting.swift` has priority colours and `DueFormatter`).

Data layer (already on master): `HITListSchemaV1` versioned schema + `HITListMigrationPlan`
(`HITList/Models/SchemaVersions.swift`; read its header rules before touching any `@Model`;
`SchemaTests` pins entity hashes and fails on any shape change). `Deduplicator` runs at launch and
2 s after each successful CloudKit import, triggered by `Notification.Name.cloudKitImportSucceeded`
posted from `CloudSyncMonitor.record`. `SeedIdentity` (HITListCore) gives seeded records stable ids.
The store lives in the App Group container (`HITList/Support/AppGroup.swift`; `AppGroup.defaults` for
settings; `ModelContainerFactory.groupStoreURL`). `HITList/Support/Debouncer.swift` exists.
`TaskActions` (create, toggleCompletion with recurrence roll-over, reschedule, delete, seeding).

## Environment (each of these cost hours to learn)

- Every xcodebuild / swift / xcrun command needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  (xcode-select points at CommandLineTools). Xcode 27.2, macOS 26.7.1.
- The Xcode project is generated: edit `project.yml`, run `xcodegen generate`; never hand-edit the
  xcodeproj. `HITList/HITList.entitlements` is generated from `project.yml`;
  `HITList/HITList-macOS.entitlements` is hand-maintained. Do not add entitlements unless your brief
  says so. Never add `com.apple.developer.icloud-container-development-container-identifiers`.
- Always build signed (`-allowProvisioningUpdates`); unsigned builds crash in CloudKit.
  Simulator: `-destination 'platform=iOS Simulator,name=iPhone 17'`. Mac: `-destination 'platform=macOS'`.
- Tests: `cd HITListCore && swift test`; app tests: `xcodebuild test -project HITList.xcodeproj
  -scheme HITList -destination 'platform=macOS' -allowProvisioningUpdates` (and the simulator destination).
- Logs: `/usr/bin/log show --info --last 5m --predicate 'subsystem == "com.trammells.hitlist"'`.
  Plain `log` is a zsh builtin and prints nothing; `--info` is required. Categories: sync, storage, dedupe.
- CloudKit.framework is linked explicitly on purpose (macOS 26 sandbox bug) and
  `CloudSyncMonitor.refreshAccountStatus` is a real CKContainer call for the same reason. Keep both.
- Production CloudKit schema is additive-only forever. Never rename/delete/retype a field.
- The real Mac store: `~/Library/Group Containers/UC8N98H3RT.com.trammells.hitlist/HITList.store`.
  Copy it before any destructive test. Never call `ModelContainer.deleteAllData()`; never delete
  objects as a "reset": deletions mirror to CloudKit and wipe every device.
- `scripts/release.sh` uploads to App Store Connect: never run it, never edit it.
- The home-server backup prototype (`server/`, `BackupService.swift`) was removed on 2026-11-05; do not rebuild it.
- Work in the git worktree you were started in, on its branch. Commit per sub-item with clear
  messages ending in `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push, do not
  open a PR, do not merge, do not switch branches. Touch only the files your brief lists; another
  session is editing the rest of the app at the same time.
- George reads instructions only in chat. Anything they must do goes in your final message with exact
  commands or click paths. Write no documents except the dev/ROADMAP.md status row your brief names.
- Final message always includes: what changed per commit, test counts before/after, how you verified
  it running (simulator and/or Mac), the branch name, and anything George must do.

## How sessions run (from 2026-11-04, round 9)
Sessions are Claude Code sessions the desktop app starts from the supervisor's session (an Opus 5.5 session
following `dev/SUPERVISOR.md`) on George's subscription: each in its own git worktree on a branch named after its
brief, cut from master. The supervisor reads each final report, merges, tests and prepares the release; George
runs `scripts/release.sh`. TestFlight build 14 (0.4.1) is live on George's devices and about to go to friends as
external testers; the next upload is 0.5.0 (15). Production's CloudKit schema is V3 (deployed 2026-11-03);
session 34 adds V4 (`Profile`), which George must deploy to Production before 0.5.0 uploads.

**Your own simulator.** Several sessions run at once and the shared "iPhone 17" simulator would get every
session's build installed over the others'. Make your own at the start and delete it at the end:
`xcrun simctl create "HITList-NN" "iPhone 17"` (NN = your brief number; it prints the UDID), boot it, build with
`-destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath build.noindex/sim`, launch it with the iOS
Simulator tool using that UDID, and run iOS tests as `SIMULATOR=HITList-NN scripts/test.sh ios`. When done:
`xcrun simctl shutdown <UDID>` then `xcrun simctl delete <UDID>`, and say so in the report. Never touch another
session's simulator, never quit George's `/Applications/HITList.app`, and quit any Debug Mac app you started.

## Round 16 (2026-11-10; briefs 70–73 in parallel, all four at once; `ROUND-16.md` says why)
The supervisor is a Fable 5.2 chat; sessions are Opus 5.5 as before (commits end `Co-Authored-By: Claude Opus 5.5
<noreply@anthropic.com>`). **The version stays 0.9.0**: the next upload is 0.9.0 (21), a new build of the same version,
and its notes are the supervisor's (`CHANGELOG.md` `## 0.9.0 (21)`, `WhatsNew.swift`). Xcode is 27.2 (SDK 27.2), this
Mac macOS 26.7.1. Brief 72 adds schema V6 (`Switchboard`, two `TaskItem` fields); George deploys it before the build.
- Ownership: 70 `mac-chrome-27` (xhigh) the Mac's sidebar, toolbar, search field and window: `SidebarView`,
  `ContentView`, `ScreenMenu` (Mac), `QuickAddEntry` (Mac toolbar item), `Views/Search/*`, `ListChrome`, the Mac Settings
  sidebar, `MacWindowKeeper`. 71 `quick-add-monthly` (high) core's `QuickAddParser`, `DateExpression`, `RecurrenceRule`,
  the Repeat card's words. 72 `switchboards` (xhigh) the models and schema, `Views/Flipboard/*`, core `FlipboardSwitch`,
  `FilterableTask`, `TaskOrdering`, `GroupedOrdering`, snapshot and backup, the switch lines of notifications, Spotlight,
  Claude and Intents. 73 `browse-and-bolt` (high) `BrowseView`, `Views/Groups/*`, `BoltSlamMotion`, the slam's lines in
  `SyncStatusViews`. Nobody: `scripts/`, `dev/briefs/`, `CHANGELOG.md`, `WhatsNew.swift`, `WhatsNewPopout`, the
  `SettingsTests` What's New pin, `project.yml` beyond adding files, `TaskRow`, `HITTokens`.
- **UI tests go in a file of your own** (`HITListUITests/<Yours>UITests.swift`): three rounds of merges conflicted in
  the shared `HITListUITests.swift`. Only brief 72 edits that file, and only its two Flipboard tests.
- **A friend's Mac runs macOS 27.2 and nobody here has it** (no VM, no CI runner). Anything you draw on the Mac must
  not lean on what the system decides by OS version or by which view holds the keyboard: a system list selection, a
  toolbar's glass or background, a sidebar's icon size. Draw it or pin it with an explicit value (brief 70 does this
  for the window's chrome; follow it in anything new).
- A switch is no longer a task by default (brief 72): when your screen lists tasks, call core's rules
  (`TaskOrdering`, `FlipboardSwitch.listing`) and never judge a switch yourself.

## Round 11 (2026-11-05; briefs 47–52 run in parallel, all six at once)
Next version 0.7.0 (17). Session 48 adds schema V5 (`TaskItem.reminderDate`); George deploys it before 0.7.0.
Read `dev/briefs/HIG-NOTES.md` (Apple's guidelines as they apply here) before designing anything visible.

**Seeing the Mac app (new, 2026-11-05).** George granted screen recording, so a session can capture its own Debug
Mac app's window (never the whole screen, which shows George's own windows):
1. Build: `xcodebuild build -project HITList.xcodeproj -scheme HITList -configuration Debug -destination
   'platform=macOS' -derivedDataPath build.noindex/mac-NN -allowProvisioningUpdates -quiet`.
2. Run it on its own store with sync off for that process only:
   `HITLIST_STORE_SUFFIX=sNN build.noindex/mac-NN/Build/Products/Debug/HITList.app/Contents/MacOS/HITList -disableCloudKit YES -seedSampleData &`
   (`-disableCloudKit YES` is a launch argument: never write `disableCloudKit` into the app-group defaults, which
   George's real app reads; only a schema push run keeps CloudKit on, still with its own suffix.)
3. `scripts/window-shot.sh <pid> build.noindex/shot-NN.png`, then Read the PNG (shrink it first with
   `sips -Z 1400`). Quit the Debug app with `kill <pid>` when done; never touch `/Applications/HITList.app`.
4. Click and type in it (George granted Accessibility, 2026-11-05): `scripts/window-drive.sh <pid> click X Y wait 1
   type "Call Sam p1" key escape shot build.noindex/s.png` (points from the window's top-left = capture pixels / 2;
   actions click, dclick, move, type, key, wait, shot). It refuses anything but a Debug HITList under `build.noindex`
   or the Simulator, acts only while that app is frontmost (George may be at the Mac: it stops if he takes over), and
   hands focus back afterwards. Keep runs short. iPhone/iPad: your own simulator as before; ask George once for tap access and carry on meanwhile.

**Driving the iPhone app without the panel permission (from round 12).** `HITListUITests` (XCUITest, its own
scheme) taps and types through the real app: `SIMULATOR=HITList-NN scripts/test.sh ui`. Add a test of your own beside
`testTabsAndQuickAdd` for your screen; launch with a fresh `HITLIST_STORE_SUFFIX` and `-disableCloudKit YES -hideTips`
(a first-run tip takes the first tap); wait for a closing card to go before the next tap (taps during its slide are
swallowed); keep screenshots with `XCTAttachment` and export them with `xcrun xcresulttool export attachments --path
<.xcresult> --output-path <folder>`. Stable identifiers: `quickAddButton`, `quickAddTitle`, `quickAddSave`, `tab-<name>`,
`browseButton`, `viewOptions`, `syncBolt`.

**Decisions from 2026-11-05 (George):** no login system ever (the Apple account is the identity; profiles serve
Shared Tasks); the Claude integration is off and hidden by default, its privacy choices shown only once switched on;
"Delight" is called "Extras"; a quick-add highlight is removed by a click/tap or by Backspace right after it; "!"
reminder phrases light up only once complete (after a space); `!15m` = 15 minutes from now, `!15mb` = before the due
time; the Discard question sits inside the card it concerns.

## Round 13 (2026-11-07; briefs 57–60 in parallel; `ROUND-13.md` says why)
Next version 0.7.2, or 0.8.0 if 0.7.2 shipped first (`ROUND-13.md`). No schema change; George deploys three
`TaskItem` fields that were missing from Production (`deadline`, `locationName`, `flipPeriodStart`). Ownership: 57
`TaskListView`, `InboxView` (not its "Review Inbox…" line), `ListChrome`, `ScreenMenu`, `BrowseView`, `SidebarView`,
`ProjectEditorView`, `SettingsPreferences`, new `Views/Groups/*`, new core `GroupedOrdering`; 58 `MobileTabBar`,
`MobileShell`, `TapHaptic`, `HITMotion`, `MobileChromeTests`; 59 `Views/Flipboard/*`, `TaskRow`, core `TaskOrdering`,
`FilterQuery`, `FilterableTask`, new core `FlipboardSwitch`, `UpcomingSchedule`, the board model, `DuoNextDays`,
`SpotlightSync`; 60 `Views/Inbox/InboxProcess*`, `InboxZeroView`, `InboxText`, `InboxPicker`, the "Review Inbox…" line
of `InboxView`, new core `InboxReview`. `HITTips.swift`: one tip each (57 `#`/`@`, 59 Flipboard, 60 review).

**New since round 12.** `-seedDemoData` on a side store fills it with a believable week (`TaskActions.demoLines`; the
README's screenshots came from it). `-seedSampleData` must set every optional field (`CloudKitSchemaTests` fails
otherwise) and `release.sh` fails its preflight while Production lacks a field the models have. The sync watchdog
counts only the task store's entities: TipKit's `Core*Record` saves post `ModelContext.didSave` too. The iOS build
no longer runs on a Mac (`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO`): a Mac check means the macOS build, never the
iPad app in a Mac window. In a test, keep the `ModelContainer` in a `let` for the whole test (a `ModelContext` does not
retain its container; `ModelContainerFactory.preview().mainContext` alone traps on the next fetch).

## Round 14 (2026-11-07 evening; briefs 61 and 63 in parallel, 62 after 61 merges; `ROUND-14.md` says why)
Next version 0.8.1 (0.8.0 shipped as build 18). No schema change. Ownership: 61 `TaskListView`, `InboxView`, `InboxText`,
`BrowseView`, `ListChrome`, `ScreenMenu`, `Views/Groups/*`, `SettingsPreferences`, `HITTips`, core `GroupedOrdering` + new
`SearchIntent`, `GroupsTests`, the Groups and Review UI tests; 63 `MobileShell`, `MobileTabBar`, `TaskRow`, `HITTokens`,
`Views/Duo/*`, `MobileChromeTests`, its own UI test; 62 (later) `Views/Shared/*`, `Services/Sharing/*`, the list views,
`Upcoming/*`, `TaskRow`, `SidebarView`, `PopoutController`, core `FilterableTask` + new `ListRow`. The rules of the round
are in `ROUND-14.md` and SUPERVISOR §7 (a name once, large titles, one control, the three sorts, filters in search).

## Round 15 (2026-11-08; briefs 64–69 in parallel, all six at once; `ROUND-15.md` says why)
Next version 0.9.0 (0.8.2, the supervisor's fix for the Mac's invisible picker cards, may ship before the round merges).
No schema change. Ownership: the table in `ROUND-15.md` and each brief's list; where two briefs share a file, each
names its region. New facts:
- The Mac's picker cards live on a layer in the window's frame view (`PickerLayerHost.host(in: window)`): with the Xcode
  27.2 SDK a SwiftUI content view draws over any AppKit view added inside it. Never draw over SwiftUI that way.
- A Debug Mac app has the real app's bundle id and may restore its saved window state and open no window: launch it
  with `-ApplePersistenceIgnoreState YES` beside `-disableCloudKit YES`, e.g. `open -g -n --env HITLIST_STORE_SUFFIX=sNN
  build.noindex/mac-NN/Build/Products/Debug/HITList.app --args -disableCloudKit YES -hideTips YES -ApplePersistenceIgnoreState YES`
  (add `-seedDemoData YES` the first time for a believable week).
- George's screenshots for this round: `/Users/gtrammell/Desktop/HITList/build.noindex/round-15/` (outside git; read by
  that absolute path).
- Your report includes screenshots of every screen you changed, on both platforms where it exists, and names anything
  that looks alike or that you could not check (SUPERVISOR §4 step 8 applies to sessions too).

## Round 16 record (2026-11-10; sessions 70–73 merged for 0.9.0 (21))
Four sessions at once on George's turn, all Opus 5.5, supervised by a Fable 5.2 chat: 70 `mac-chrome-27` (xhigh, 9
commits), 71 `quick-add-monthly` (high, 7), 72 `switchboards` (xhigh, 9, schema V6), 73 `browse-and-bolt` (high, 4).
Merged 71, 73, 70, 72; conflicts only in `dev/ROADMAP.md` (rows kept) and the generated project (regenerated).
Supervisor follow-ups: Group and label counts leave out unlisted switches (`SidebarCounts.group`, `.label`), the editor's
"Add to Flipboard" words, the demo week's green flipboard label, `NewSwitchboardRow` at the Flipboard's foot (on iPhone
"New Switchboard…" sat only behind a long press on the sound button), notes per build (`WhatsNew.Entry.build`,
`release.sh`'s `## 0.9.0 (N)` check and stamp).
After the round:
- Core: `SwitchboardSchedule` (a board's day and week from its reset time), `FlipboardSwitch.listing` (a switch is
  `.hidden` unless opted in and due), `FilterableTask.filterSwitchOptedIn` and `filterSwitchboard`,
  `RecurrenceRule.Place` (a day, the last day, a weekday in the month, a date in the year; a sixth part of the encoded
  string that builds before 0.9.0 (21) ignore), `QuickAddParser+Repeats.swift`.
- Mac: `Views/MacChrome/*` (`MacSidebarRow`, `MacToolbarChrome`, `ToolbarPill`, `WindowFocusGuard`). The sidebar is a
  scroll view of our rows, not a `List`; the toolbar's background is hidden and a `Theme.background` band is drawn
  under its items. Debug arguments: `-focusSearchAtLaunch YES` forces macOS 27's bad case (a text field holding the
  keyboard at launch), `-flipboardNow` sets the Flipboard's clock for screenshots.
- Still the system's on the Mac, so macOS 27 can still differ: whether the sidebar column floats or sits flush, the
  toolbar's height and gaps, menus, and the task list's own selection highlight and header hairlines (`TaskListView`
  is a system `List`). Owning the column's shape means our own split view and top bar: a round of its own.
Left for later: no swipe to delete on the iPad's full sidebar (`SidebarView`); a long repeat chip ("Second Tuesday of
the month") runs past the editor card's edge until scrolled; the Repeat card was checked on iPhone only; VoiceOver and
Full Keyboard Access on the new Mac sidebar are unchecked; typing a letter no longer jumps to a sidebar row; a
weekly board's timed switch is due on the reset day only (no weekday of its own); two Apple accounts sharing still
untested; side stores `HITList-s70a`, `HITList-s71`, `HITList-s72a`, `HITList-s73` and `HITList-sup*` in the Mac app
group folder (delete by hand in Finder).

## Round 15 record (2026-11-08; sessions 64–69 merged for 0.9.0)
Six sessions at once on George's turn, all Opus 5.5: 64 `shared-group` (xhigh, 8 commits), 65 `editor-quick-add`
(xhigh, 7), 66 `mac-chrome` (high, 6), 67 `type-scale` (xhigh, 3), 68 `bolt-slam` (xhigh, 4), 69 `flipboard-add` (xhigh,
6). Merged 68, 69, 67, 65, 66, 64; conflicts only in `dev/ROADMAP.md`, the generated project and `HITListUITests.swift`
(65's new test kept, 64's replacement of 62's kept). Supervisor follow-ups: 67's measured Mac row details (a light circle
8 pt from the title and 1 pt lower, a 1 pt date icon; `TaskRowMetrics`), Group dots in the editor's Move to… and its
typed-Group row, the Mac Extras subtitle; George's tweaks (the "+" in the Confirm pill's look, tips outside the
quick-add card, the Flipboard lights). Left for later: the Priority and Repeat cards' buttons take keyboard focus only
with Full Keyboard Access (`PopoutPickers`); `TokenHighlightField`'s `apply` can overwrite a letter just typed when its
owner is rebuilt mid-keystroke inside a keyboard-height `GeometryReader` (69's finding, worked around in the Flipboard
card; a guard in `apply` would fix it everywhere); on iPhone the toolbar pill is still about 4 pt wider on the
Flipboard than on a list: iOS 26 sizes a toolbar menu by its glyph and ignores a frame on the menu, on its label and on a
container label (tried all three; only a plain Button took a width), so the fix is a narrower glyph or a different
control there; on a simulator that behaves as if a hardware keyboard is attached (the long-lived "iPhone 17"), the
editor's date card does not open while the title has focus, so run UI tests on a fresh simulator, and an iPad with a
hardware keyboard may show the same; the quick-add tips show in the floating Mac card and the iPhone card
but not in the Mac's inline and board cards; two Apple accounts sharing still untested; side stores `HITList-s64*`,
`HITList-s65`, `HITList-s66`, `HITList-s68*`, `HITList-s69*`, `HITList-s15*` and `SharedTasks-s64a/b.json` in the Mac app
group folder (delete by hand in Finder).

## Round 14 record (2026-11-07/08; sessions 61–63 merged for 0.8.1)
61 `lists-cleanup` (xhigh, 6 commits), 63 `duo-and-shell` (high, 3) at once, then 62 `shared-in-lists` (xhigh, 6) on
the merged lists. No conflicts. Supervisor follow-ups: Upcoming's iPhone title made large; the disabled "Sort"
placeholders removed from Group, label and filter lists; day headers hide the day on their rows in every list; the
Duo test sums `IslandMetrics.sideChromeHeight`; Browse's Inbox count includes shared tasks. The supervisor looked at
every screen on both platforms before the hand-over (ROUND-14's list) and sent the screenshots with it.
Core API after the round: `ListSort` (priority/group/date) with `Preferences.inboxSort`/`todaySort`; `SearchIntent`
(Browse's field: text or a filter query); `ListRow` (a task of yours or a `SharedRow`) feeding `TaskOrdering`,
`GroupedOrdering`, `FlipboardSwitch.listing` and `UpcomingSchedule`; `SharedRows` (observable, actions through the
shared store); `SidebarItem.sharedList(id)`. Left for later: the Mac shared editor panel is drawn by the list column
rather than `PopoutHost`; a shared list's screen keeps the Shared screen's card look; the badge and morning summary
count neither shared tasks nor red switches as George means them; two Apple accounts untested for shared rows; side
stores `HITList-s6*.store` and `SharedTasks-s62*.json` in the Mac app group folder (delete by hand).

## Round 13 record (2026-11-07; sessions 57–60 merged for 0.8.0)
Four sessions at once on George's turn, all Opus 5.5: 57 `groups` (xhigh, 9 commits), 58 `tab-motion` (high, 4),
59 `flipboard-intervals` (xhigh, 6), 60 `review-inbox` (high, 5). Merged 59, 57, 58, 60; the only conflicts were the
shared `HITListUITests.swift` (both sides kept, twice). Supervisor follow-ups: 59's list-view lines applied by hand to
57's reworked `TaskListView`, `InboxView` and `BrowseView` (`todaySection(of:)` in both Today layouts,
`Flipboard.completion`/`completeRow`/`undo` in the completion paths, `now:` passed to `inbox`, `sorted` and `search`);
`GroupedOrdering`'s default `order` became a closure once `TaskOrdering.sorted` gained `now:`, and its default
`sectionOf` is `todaySection(of:)` so a grouped and an ungrouped Today agree about switches; the motion table in the
design-system README gained `tabPill` and `tabSwitch`; the 0.7.2 notes were renamed 0.8.0 with the round's lines.
Sessions' notes, patches and screenshots live in `~/Library/Application Support/Claude/side-session-notes/<id>/`.
Left for later: the task editor's Group row shows a coloured "#" rather than the Group's dot (`TaskPopout`); the
morning summary and the app badge still count an overdue red switch as overdue; two side stores `HITList-s59a.store`
and `HITList-s59b.store` sit in the Mac app group folder (listing it from a shell hangs; delete by hand).

## Round 12 (2026-11-05; briefs 53–56 in parallel, the build friends get)
Still 0.7.0 (17), unreleased: add to its notes, never a new version. No schema change. Ownership: 53 profile menu
(`ProfileMenu`, Browse's profile button, new `WhatsNewPopout`/`BetaFeedback`); 54 `SyncStatusViews`/`SyncState`
(bolt); 55 Claude settings + `ClaudeAccess` default + `HingeCreak*` + the Extras hinge row; 56 `Views/Tips/*`,
`UpcomingBoard`, `TaskRow` meta line, `HITListUITests/*`. The official Claude logo is not used (Anthropic's trademark
guidelines require their prior approval).

## Round 12 record (2026-11-05; sessions 53–56 merged into 0.7.0 (17), the Friends build)
53 `profile-feedback` (profile menu: What's New popout, Send Beta Feedback mail to george@trammells.com with a
version/device footer, version line), 54 `bolt-strike` (bolt 12.65 pt, `BoltStrikeGate` + strike motion, Debug
`-boltStrikeDemo YES`), 55 `claude-hinge-polish` ("Only tasks with @claude" default/left, audio audit test, wooden creak
at ≤ −18 dBFS, "Creaky hinge"), 56 `release-polish` (tips wait for `HITTip.settled`, inline quick-add tips, board meta
flow layout, Duo board safe area, `FirstRunUITests`). All High. Supervisor: merged 47's single-writer focus fix; found
that interactive Liquid Glass on the iPhone "+" ignored its first tap after `allowsHitTesting` came back (the button is
now removed and re-inserted; `testPlusOpensTheNextCardRightAfterAnAdd`); toast tail truncation;
`CADisableMinimumFrameDurationOnPhone`; the official Claude logo NOT used (Anthropic's trademark guidelines require
their prior approval). 0.7.0's release stopped at the Shared Tasks container's schema check, so it ships as 0.7.1 (17)
with George's last fixes: the Mac's Send Beta Feedback copies the address instead of opening Mail, and the bolt
strikes only on the first good sync after launch, after ≥ 1 min away, or after ≥ 1 min of sync trouble.

## Round 11 record (2026-11-05; sessions 47–52 merged for 0.7.0 (17))
Six sessions on George's turn: 47 `highlight-engine` (xhigh), 48 `reminder-language` (xhigh, schema V5), 49
`extras-claude-polish` (High), 50 `duo-hinge` (xhigh), 51 `shared-tasks` (max), 52 `tips-spotlight-cleanup` (High).
Mid-round the supervisor added `scripts/window-drive.sh` (George granted Accessibility) and sent it by `SendMessage`;
47, 48, 49 and 52 then drove their Debug Mac apps for real and found bugs the hosted tests missed (pointer flicker
from SwiftUI's own cursor handling, box geometry). 50 drove the real fold through Device Hub's AX buttons.
51 chose a second CloudKit container `iCloud.com.trammells.hitlist.shared` (registered by automatic signing,
permanent), `CKSyncEngine`, a JSON store per task store, push routing in `SyncAppDelegate`, and an iOS scene delegate
for share acceptance; off by default. Supervisor follow-ups: Claude `reminder_at` and add_task wording, the
tips' attach lines, README reminder grammar, reminder/summary taps routed through `IntentRouter` (nothing listened for
`.openTask`), side-store runs keep their own settings suite (`AppGroup.suiteName(suffix:)`), privacy policy sections,
`release.sh` drift check over both containers. Lessons: launch a Debug Mac app with `open -g -n --env
HITLIST_STORE_SUFFIX=… <app> --args -disableCloudKit YES` so it never takes George's keystrokes, then `open <app>`
to bring it forward for window-drive; check nothing covers the window first. Known open: on the Duo's inner display
on its side the system bar overlaps the board's last column; a friend accepting a Shared Tasks link is untested
(George tests with friends on TestFlight).

## Round 11 ownership
- `47-highlight-engine` (xhigh): `TokenHighlightField`, new `Views/Popouts/HighlightText/*`, the field's call sites in
  `QuickAddPopout`/`CompactQuickAddCard`, `HighlightAreaTests`, new `HighlightFieldTests`.
- `48-reminder-language` (xhigh, merged last): parser (+Disabled), `DateExpression`, `Snapshot*`, `QuickAddDraft`,
  `Models.swift`, `SchemaVersions.swift`, new `SchemaV4Models.swift`, notifications, `TaskActions` reminder paths,
  `SnapshotBuilder`, `Deduplicator` (field), `QuickAddPopout` Reminder chip region, reminder picker, `TaskPopout`/`Editor/*`
  Reminder pill region, `TaskRow` meta bell, `SchemaTests`, new `ReminderDateTests`.
- `49-extras-claude-polish` (High): `ClaudeSettingsSection`, `Services/Claude/*`, helper messages, `docs/connect-claude.md`,
  `PopoutController`, "Delight" strings (`DelightSettingsSection`, `MacSettingsSection`), `SidebarView`/`ProfileMenu`
  spacing, `CompactQuickAddCard` + `QuickAddPopout` compact Discard, `InlineAddRow` in `QuickAddEntry`.
- `50-duo-hinge` (xhigh): `Views/Duo/*`, `MobileShell`, `MobileTabBar`, `ContentView`, `PopoutHost`, `UpcomingView.showsBoard`,
  `TaskPopout` fold continuity, `Views/Flipboard/*` column count, new `HingeCreak*`, one row line in `DelightSettingsSection`.
- `51-shared-tasks` (max): new `Services/Sharing/*`, `Views/Shared/*`, its own model/schema, `SyncAppDelegate` share
  acceptance, `BrowseView` (preview row + entry), one line in `SidebarView`, entitlements/`project.yml` only if a
  second container is needed.
- `52-tips-spotlight-cleanup` (High): new `Views/Tips/*`, `Services/Spotlight/*`, `Services/Intents/*`, one line each in
  `HITListApp` and `AccountSwitch`, About sections, `MacSettingsPage`, `SettingsRouter`, dead files nobody owns.
- Nobody: `scripts/`, `dev/briefs/`, `CHANGELOG.md`, `WhatsNew.swift`, the `SettingsTests` version pin.

## Round 10 record (2026-11-04; sessions 39–46 merged for 0.6.0 (16))
Eight desktop-app sessions, all started on George's own turns: 39 `board-inline-add` (High), 40 `profile-chrome`
(High), 41 `quick-add-polish` (High), 42 `sync-profile-hardening` (xhigh), 43 `claude-connector` (xhigh), 44
`holiday-delight` (High), 45 `iphone-duo` (xhigh), 46 `app-intents` (High, started mid-round). Cross-session fixes went
by `SendMessage` to the owning session while it still ran (42's `ProfileStore.shown` to 40; 41's Discard findings to
39 and 45). Supervisor follow-ups: `PopoutController` listens for `.accountDidSwitch`; the holiday accent on the "+";
privacy policy sections for Claude and Siri; 46's `.intentRouting` lines in the shells. No schema change. Known and
open: the account-switch banner overlaps the large title on iPhone; Claude's completions post
`.claudeDidCompleteTask` with no Undo toast listening; the Duo inner display shows the iPhone Upcoming list
(`UpcomingView.showsBoard` is iPad-idiom only); editor typing is lost when the editor moves sheet ↔ column across a
fold; the Mac lists' `InlineAddRow` × does not ask Discard. Lesson: a session given a Debug probe on the Mac must set
`HITLIST_STORE_SUFFIX`, or an in-memory run can write into the TestFlight app's app-group defaults (39 did once).

## Round 10 ownership (2026-11-04; briefs 39–45 run in parallel, all seven at once)
Next version 0.6.0 (16). No schema change this round: a fix that needs one stops and reports. Every session makes its
own simulator (`HITList-NN`; 45 an iPhone Duo, 39 an iPad) and deletes it at the end.
- `39-board-inline-add` (High): `UpcomingBoard` (+ card file), new `CompactQuickAddCard`, `QuickAddPopout.swift`,
  `QuickAddEntry.swift` (Mac focus), `UpcomingBoardTests`, new `CompactQuickAddTests`.
- `40-profile-chrome` (High): `MobileTabBar`, `BrowseView`, `SidebarView`, new `Views/Account/ProfileMenu.swift`,
  `SettingsRouter`, `MobileChromeTests`, new `ProfileMenuTests`.
- `41-quick-add-polish` (High): parser (+Disabled), `TokenHighlightField`, `QuickAddDraft`, `TaskPopout`/`Editor/*`
  (× only), `HighlightAreaTests`, `PopoutTests`.
- `42-sync-profile-hardening` (xhigh): `ProfileStore`, `Deduplicator`, `CloudSyncMonitor`, `AccountWatch`,
  `Services/Sync/*`, `ModelContainerFactory`, `LocalBackup`, notifications (account switch), `AccountSettingsSection`,
  `ICloudSettingsGroups`, `SyncStatusViews`, new `AccountSwitchTests`.
- `43-claude-connector` (xhigh): new `Services/Claude/*`, new helper target, `project.yml` target, Mac entitlements,
  new `ClaudeSettingsSection`, one line in `SettingsView`, the Claude entry in `MacSettingsSection`, `docs/claude.md`.
- `44-holiday-delight` (High): new HITListCore `Holidays.swift`, `Views/Delight/*`, `Support/Delight/*`,
  `DelightSettingsSection`, `TaskRow` overlay hook only.
- `45-iphone-duo` (xhigh): `ContentView`, `MobileShell`, `PopoutHost`, new `Views/Duo/*`, new `DuoLayoutTests`.
- Nobody: `scripts/`, `dev/briefs/`, `CHANGELOG.md`, `WhatsNew.swift`, the `SettingsTests` version pin, everything else.
  ROADMAP: only your row. `project.yml`: add files only (43 also adds its target).

## Round 9 record (2026-11-04; sessions 34–38 merged for 0.5.0 (15))
Five desktop-app sessions started by the Opus 5.5 supervisor: 34 `accounts-profile` (xhigh, 171 turns), 37
`highlight-merge-override` (High, 96), 38 `mac-upcoming-board` (xhigh, 158) first; then 35 `tabs-browse` (High,
26) and 36 `editor-space-confirm` (High, 247), cut from master after the first three merged. Sessions in the
second wave were proposed as cards George started: the app refuses `start_session` on a turn opened by a
background-task or session event. Supervisor follow-ups: the sync bolt and dot are grey for someone who never
used iCloud (`SyncBolt.everSignedIn`), an Upcoming day's add card keeps the day when a priority/label/reminder sits
beside the time, stale comments. Schema V4 (`Profile`) is in CloudKit Development; George deploys it before 0.5.0
uploads. The repo is public and GitHub Pages serves `docs/` (privacy policy at
https://aeronyx.github.io/HITList/privacy/). Sessions need George to grant simulator tap access in their own
panel; 35 never got it, so the supervisor tapped its menus.

## Round 9 ownership (2026-11-04; briefs 34–38; 34, 37, 38 first, then 35 and 36)
- `34-accounts-profile` (xhigh): `Models.swift`, `SchemaVersions.swift`, new `SchemaV3Models.swift`,
  `ModelContainerFactory` model list, new `Services/ProfileStore.swift`, `Deduplicator` (profile merge),
  `SyncLog` category, new `Views/Settings/AccountSettingsSection.swift`, one line each in `SettingsView.swift`
  and the Mac settings section list, `AboutSettingsGroup`/`MacAboutSection` (privacy link), `Diagnostics.swift`,
  `ICloudSettingsGroups.swift` (account lines), new `docs/`, `SchemaTests`, new `ProfileTests`.
- `35-tabs-browse` (High): `Views/Tabs/*` (iPhone), `BrowseView`, `ScreenMenu` iPhone branch, start tab in
  `SettingsPreferences`/`GeneralSettingsSection`, `screenChrome` call-site items, `MobileChromeTests`.
- `36-editor-space-confirm` (High): `TaskPopout`, `Editor/*`, `QuickAddPopout` footer + title submit,
  `TokenHighlightField` submit/Return lines, `PopoutHost` detents and editor dismiss, `PopoutTests`.
- `37-highlight-merge-override` (High): HITListCore `QuickAddParser` (+Disabled), `TokenHighlightField` areas,
  drawing and tap targets, `QuickAddDraft` (`disable`, reminder text), new `HighlightAreaTests`.
- `38-mac-upcoming-board` (xhigh): `Views/Upcoming/*` (iPhone branch unchanged), new `UpcomingBoard`,
  `UpcomingSchedule`, `TaskRescheduling`, `QuickAddContext` day context, `UpcomingScheduleTests`, new
  `UpcomingBoardTests`.
- Nobody: `scripts/`, `dev/briefs/`, `CHANGELOG.md`, `WhatsNew.swift`, the `SettingsTests` version pin, everything
  else. ROADMAP: only your row. `project.yml`: add files only.

## Round 8 record (2026-11-03; sessions 31–33 merged for 0.4.1 (14))
Three desktop-app sessions on the subscription, all merged by Fable the same day: 31 `quick-add-language`
(High, 97 turns), 32 `subtasks-editor` (xhigh, 137 turns), 33 `feel-and-chrome` (High, 143 turns). Fable's
follow-ups after the merge: the editor's time setters and `TaskActions.reschedule` call
`TaskActions.syncRepeatTime(of:)`; sidebar and Browse counts skip sub-tasks. Schema V3 (`TaskItem.parent`)
is in CloudKit Development; George deploys it to Production before 0.4.1 uploads.

## Round 8 ownership (2026-11-03; briefs 31–33 ran in parallel; kept for the record)
- `31-quick-add-language` (branch `quick-add-language`, High): HITListCore `DateExpression`, `QuickAddParser`
  (+Disabled), `RecurrenceRule`, `TaskOrdering.priorityThenDue`, `FilterQuery.defaultSort`; `TaskActions`
  roll-over/`setRecurrence`; `QuickAddPopout` suggestion row (removal); `QuickAddContext`; `QuickAddDraft`
  `restoredDraft`; help text; their tests.
- `32-subtasks-editor` (branch `subtasks-editor`, xhigh): `Models.swift`, `SchemaVersions.swift`, new
  `SchemaV2Models.swift`, `SchemaTests`; `TaskActions` (all but the roll-over's time); `Deduplicator`;
  `Snapshot`/`SnapshotBuilder`; `TaskPopout.swift` + new `Views/Popouts/Editor/`; `QuickAddPopout` option bar
  + subtask lines; `QuickAddDraft` subtask lines; `TaskRow` meta line; subtask exclusion in `TaskOrdering` /
  `FilterQuery`; `project.yml` (adding files only).
- `33-feel-and-chrome` (branch `feel-and-chrome`, High): `SyncAppDelegate` Mac half, `HITListApp.swift`
  window lines, new Mac window helper; `QuickAddEntry.swift`; `CompletionFeedback.swift`, new `TapHaptic.swift`;
  `CompletionToast.swift`, `CompletionMotion.swift`; `PopoutHost` toast placement; list toast call sites;
  one haptic call in `QuickAddPopout`; `HITTokens.swift`, `IslandMetrics`; `TaskRow` line height.
- Nobody: `scripts/`, `dev/briefs/`, `CHANGELOG.md`, `WhatsNew.swift`, everything else. ROADMAP: only your row.

## Where things stand (2026-10-31, after round 3 and Fable's follow-ups)
On master and in TestFlight build 5: design system (`HITList/Support/DesignSystem/`, README = component
guide), Inter typeface (`HITType` roles only; never `.font(.subheadline)`), schema V2 (`reminderOffsetMinutes`,
`deadline`, `locationName`, `flipTarget`, `flipCount`, `flipPeriodStart`; V1 frozen in SchemaV1Models.swift),
shared due colours (`HITColor.due`), popouts (`HITList/Views/Popouts/`: oval quick-add card with the "+"
options bar, reminder offsets `!15mb`, task popout with Deadline/Location), the iPhone tab shell
(`HITList/Views/Tabs/`: Inbox, Today, Upcoming, Browse, oval "+" in `MobileShell`; iPad and Mac keep the
sidebar), Today's Overdue + day sections sorted priority-then-due (`HITListCore/.../TaskOrdering.swift`), the
Inbox rule (dated tasks in any Group + undated tasks with no Group; undated grouped tasks only inside their
Group), "Group" as the user-facing word for Project, Flipboard long-press menu, faint-green lamp and charging
switches. `TaskRow` aligns the checkbox and priority badge on the title's first line and draws its second
line with `MetaItem` (never `Label`, whose List style reserves a wide icon column).

Lesson from round 3: commit after every item. Twice the runner's permission stream closed near the end of a
long session and every write (git, xcodegen) was refused from then on; work left uncommitted had to be
committed by hand afterwards.

Also on master since build 5 (Fable, 2026-10-31): `HITType.taskName` is one step above body (20 bold on
iPhone, 15 on Mac; George found 14 too small). `HITList/Support/AppInfo.swift` (`AppInfo.versionLabel` =
"0.2.0 (6)"), shown in Settings → About. `HITList/Support/Preferences.swift`: shared preference keys
(`startTab`, `defaultReminderOffsetMinutes`, `theme`, `reduceEffects`); add your own keys only as an
`extension Preferences` in a file you own. `SyncIndicatorDot` (6 pt, in `SyncStatusViews.swift`).
`Views/Settings/AppearanceSettingsSection.swift` is a stub for session 22. `CHANGELOG.md` has a section per
version; `scripts/release.sh --version X.Y.Z` (Fable only) runs the preflight tests (core, macOS, iOS) before
anything is archived and refuses a version without a changelog section. Liquid Glass (iOS 26 / macOS 26)
is allowed behind `#available` with the slate look as fallback; deployment targets stay iOS 18 / macOS 15;
the API names are listed in briefs 20 and 22 and were checked against the Xcode 27.1 SDK interface.

## Round 7 (2026-11-02; sessions 25–30, all merged for 0.4.0 (13))
- Sessions 27 `dates-and-times` (High, $4.20), 28 `quick-add-card` (High, $4.65), 29
  `completion-popout-push` (High, $7.23) ran in parallel on George's nine decisions; 30 `beta-final-review`
  (Max, $16.64) reviewed the merged result (six fixes). Self-launched from Fable's Bash; reports read from
  the task output files.
- Session 25 `sync-robustness` (Max, $36.61, 74 min, merged 2026-11-02): sync log, watchdog (5 s rule),
  CloudKit environment and push diagnostics, Settings → iCloud → Sync log, the stuck-sync relaunch, the
  Development side store. Found the Nov 1 Mac hang (an import that never ended; CloudKit refused every
  later request, NSCocoaErrorDomain 134417).
- Session 26 `beta-review` (Max, $33.89, 62 min, merged 2026-11-02): 12 core fixes, each with a failing
  test first (reset safety, in-memory fallback for a damaged store, complete backups, Debug/TestFlight
  separation, reminder rescheduling on every save, stale-reminder completion, sticky draft fields, blank
  titles, integer overflow in quick add, environment detection from signed entitlements, first-import
  grace). Nine behaviour decisions left for George are in its report (Fable's session notes).

## Round 6 (finished 2026-11-01; kept for the record)
- `24-mac-settings-page` (branch `mac-settings`): `SettingsView.swift`, `Views/Settings/*`, new
  `Views/Settings/Mac/*`, `HITListApp.swift` (Settings scene + appSettings command only), `ContentView.swift`
  (`.settings` item + screen), `SidebarView.swift`, `openAppSettings` in `Tabs/ScreenMenu.swift`,
  `SettingsTests`, new `MacSettingsTests`, its ROADMAP row.
- Nobody: everything else. Fable's build-7 polish is already on master (`Tabs/ScreenMenu.swift` layout,
  `SyncStatusViews.swift`, `Popouts/*`, `Theme.swift`, `Upcoming/*`, `Browse`, `Flipboard`).

Also on master since build 8 (Fable): `ThemePalette` has a ninth colour, `bolt`, and `SyncBolt.look(for:)`
decides the bolt's shape (filled / hollow / struck through) and colour per state; the Mac Settings page
(`MacSettingsPage`) takes the whole window: `SplitContent` sets the split view to `.detailOnly` while
`SidebarItem.settings` is selected and the page's Back (`SettingsRouter.close()`) restores the previous
list; `AddSwitchTile` is the Flipboard grid's last cell; Inbox groups by priority; Upcoming's view options
hold Show overdue and Days shown; the Mac quick-add title is a `TextEditor` with a hidden background;
`Preferences.compactRows` reaches `TaskRow`.

Also on master since build 7: `screenChrome` draws the small `SyncBolt` outside the toolbar's shared glass
(`sharedBackgroundVisibility(.hidden)` on iOS 26 / macOS 26) and then exactly two controls: the screen's
own (`viewOptions`) and the "…" with Settings… and the version on every platform; eight theme palettes;
the iPhone quick-add card is put away in one motion (`PopoutHost.retireQuickAdd`); build output lives in
`build.noindex/` and Xcode's DerivedData in `~/Library/Developer/Xcode/DerivedData.noindex` so Spotlight
never offers a stale HITList.app.

## Round 5 (finished 2026-11-01; kept for the record)
- `23-mac-pickers` (branch `mac-pickers`): `Views/Popouts/PopoutPickers.swift`, new `Views/Popouts/Pickers/*`,
  new `Support/DesignSystem/HITCalendar.swift` (+ README section, gallery entry), the chip `.popover` call
  sites and `chipBinding` plumbing in `QuickAddPopout.swift` and `TaskPopout.swift`, `PopoutTests`, new
  `PickerTests`, its ROADMAP row.
- Nobody: everything else. Fable is polishing the iPhone lists and the Mac toolbar on master at the same
  time (`MobileShell`, `TaskRow`, `TaskListView`, `InboxView`, `UpcomingView`, `PopoutHost`, `QuickAddEntry`,
  `TokenHighlightField`, `InboxProcessView`); do not touch those.

Also on master since build 6: `screenChrome` shows the "…" on the Mac too (Inbox review and Flipboard
actions live there on every platform); the iPhone shell is a bottom-aligned ZStack with
`contentMargins(.bottom, IslandMetrics.chromeHeight + 8)` on the stack (a `safeAreaInset` on the
NavigationStack did not reach the lists inside it on iOS 26).

## Round 4 (finished 2026-11-01; kept for the record)
Sessions 20 (iphone-chrome), 21 (settings-v2) and 22 (motion-themes) are merged. 20 and 21 stopped early
when the runner's 1 MB message buffer overflowed on a screenshot Read; the runner now allows 64 MB. Fable
finished brief 20's items 3–9 on master: `Views/Tabs/ScreenMenu.swift` (`screenChrome` = view-options
icon + "…" on every screen; iPhone "…" has Settings, the version and `SyncIndicatorDot`), `hitGlass` and
`HITGlassContainer` replace session 20's own guard, `IslandMetrics.chromeHeight` positions the toast,
`PopoutController.requestDelete` + one dialog in `PopoutHost` honour Confirm before deleting, the week
start preference reaches Upcoming, quick add and rescheduling, and the toast/collapse curves use the
`HITMotion` roles.

## Round 3 ownership (finished 2026-10-31; kept for the record)
- `17-mobile-tabs` (branch `mobile-tabs`): `ContentView.swift`, new `Views/Tabs/`, `TaskListView.swift`,
  `TaskRow.swift`, `SidebarView.swift`, `Views/Inbox/*`, `Views/Upcoming/*`, `Popouts/QuickAddEntry.swift`,
  `Support/Formatting.swift`, new `HITListCore/.../TaskOrdering.swift`.
- `18-quick-add-v2` (branch `quick-add-v2`): `Views/Popouts/*` except `QuickAddEntry.swift`,
  `HITListCore/.../QuickAddParser.swift` + `DateExpression.swift`, `Services/NotificationScheduler.swift`,
  `Services/Notifications/*`, `TaskActions.create`, `DesignSystem/HITChip.swift` (compact size only).
- `19-flipboard-charge` (branch `flipboard-charge`): `Views/Flipboard/*` and its tests.
- Nobody: `Models.swift`, `SchemaVersions.swift`, `SchemaV1Models.swift`, `HITTokens.swift`, `project.yml`,
  `HITListApp.swift`, `SettingsView.swift`, `scripts/`, `dev/briefs/`. ROADMAP: add only the row your brief names.
