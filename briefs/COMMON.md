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

## How sessions run (from 2026-10-31)
Sessions start with `scripts/session.sh <slug> <brief> <effort>` on George's API credit, each in its own
worktree `../HITList-<slug>` on branch `<slug>` cut from master. George pastes the final report into the
main (Fable) session, which reviews, tests, merges and releases. TestFlight build 10 (0.3.3) is live; the next upload is 0.3.4 (11).

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

## Round 7 (started 2026-11-02)
- Session 25 `sync-robustness` (Max): sync log, watchdog (5 s rule), CloudKit environment and push
  diagnostics, Settings → iCloud → Sync log. Owns `Services/CloudSyncMonitor.swift`, `SyncState.swift`,
  `AccountWatch.swift`, new `Services/Sync/`, the app-delegate hooks in `HITListApp.swift`, the iCloud
  settings groups and the Mac iCloud section. Fable owns everything under `Views/` this round (lists,
  popouts, rows) and did the build-11 feedback on master.

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
