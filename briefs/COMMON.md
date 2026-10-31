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
main (Fable) session, which reviews, tests, merges and releases. TestFlight build 2 (0.1.0) is live.

## Concurrency note (2026-10-31, round 2)
Merged on master now: design-system (`HITList/Support/DesignSystem/`, restyled editors, Settings, sidebar,
`…` toolbar menu), flipboard-polish (start-red rule, flip sound), inbox-polish (`HITList/Views/Inbox/`,
Process mode). Running next: `task-popouts` (owns `ContentView.swift`, `TaskListView.swift`, `TaskRow.swift`,
`QuickAddBar.swift`, `TaskDetailView.swift`, new `HITList/Views/Popouts/`, plus one-line hooks in
`UpcomingView.swift`, `InboxView.swift`, `FlipboardView.swift`). Anything else running at the same time must
stay out of those files.
