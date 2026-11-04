# HITList: facts every delegated session must read first

HITList ("Human-in-the-List") is George's personal Todoist-style task app: SwiftUI multiplatform
(iOS 18+, macOS 15+), SwiftData with CloudKit private database `iCloud.com.trammells.hitlist`,
pure-Swift package `HITListCore` (filter query language, quick-add parser, autocomplete, recurrence,
snapshot JSON; 43 XCTest tests) and app test bundle `HITListTests` (in-memory container, hosted in the
app, runs on iOS simulator and macOS; 21 tests). Build 1 (0.1.0) is on TestFlight on George's iPhone 16
and Mac. George uses it daily as their primary task app and will later share it with friends.
`ROADMAP.md` is the plan. Dark slate theme only, never light mode (`HITList/Support/Theme.swift`:
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
  (xcode-select points at CommandLineTools). Xcode 27.1, macOS 26.7.1.
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
- `BackupService.swift` and `server/` are deliberate unused design relics; leave them alone.
- Work in the git worktree you were started in, on its branch. Commit per sub-item with clear
  messages ending in `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push, do not
  open a PR, do not merge, do not switch branches. Touch only the files your brief lists; another
  session is editing the rest of the app at the same time.
- George reads instructions only in chat. Anything they must do goes in your final message with exact
  commands or click paths. Write no documents except the ROADMAP.md status row your brief names.
- Final message always includes: what changed per commit, test counts before/after, how you verified
  it running (simulator and/or Mac), the branch name, and anything George must do.

## How sessions run (from 2026-11-04, round 9)
Sessions are Claude Code sessions the desktop app starts from the supervisor's session (an Opus 5.5 session
following `SUPERVISOR.md`) on George's subscription: each in its own git worktree on a branch named after its
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
- Nobody: `scripts/`, `briefs/`, `CHANGELOG.md`, `WhatsNew.swift`, the `SettingsTests` version pin, everything
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
- Nobody: `scripts/`, `briefs/`, `CHANGELOG.md`, `WhatsNew.swift`, everything else. ROADMAP: only your row.

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
  `HITListApp.swift`, `SettingsView.swift`, `scripts/`, `briefs/`. ROADMAP: add only the row your brief names.
