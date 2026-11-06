# Brief: ROADMAP item 5, Sync resilience

Effort: High. Model: Opus 5.5. Run from your own git worktree (see the command in chat).

## Background

HITList ("Human-in-the-List") is George's personal Todoist-style task app: SwiftUI multiplatform
(iOS 18+, macOS 15+), SwiftData with CloudKit private database `iCloud.com.trammells.hitlist`,
pure-Swift package `HITListCore` (43 tests) and app test bundle `HITListTests` (21 tests, in-memory
container, hosted in the app on iOS simulator and macOS). Build 1 (0.1.0) is on TestFlight and runs on
George's iPhone 16 and Mac. George uses it daily as their primary task app and will later share it
with friends, so sync must be professionally robust. `ROADMAP.md` holds the plan; this session owns
item 5 only.

Master already contains items 1-3: `HITListSchemaV1` versioned schema + `HITListMigrationPlan`
(`HITList/Models/SchemaVersions.swift`), a `Deduplicator` that runs at launch and 2 s after each
successful CloudKit import (via `Notification.Name.cloudKitImportSucceeded` posted from
`CloudSyncMonitor.record`), stable seed ids (`SeedIdentity` in HITListCore), and the store in the App
Group container (`HITList/Support/AppGroup.swift`: id `group.com.trammells.hitlist` on iOS,
`UC8N98H3RT.com.trammells.hitlist` on macOS; `AppGroup.defaults` for settings;
`ModelContainerFactory.groupStoreURL` / `legacyStoreURL` / `moveStore`). `HITList/Support/Debouncer.swift`
exists. Dark slate theme only (`HITList/Support/Theme.swift`: `slateList()`, `slateRow()`,
`slateSheet()`, `Theme.accent`); never light mode.

## Environment facts (each cost hours to learn)

- Every xcodebuild/swift/xcrun command needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
  Xcode 27.1, macOS 26.7.1.
- The Xcode project is generated: edit `project.yml`, run `xcodegen generate`; never hand-edit the
  xcodeproj. `HITList/HITList.entitlements` is generated from `project.yml`;
  `HITList/HITList-macOS.entitlements` is hand-maintained. Do NOT add new entitlements in this task
  (no iCloud Documents, no ubiquity containers): the next TestFlight upload must not grow signing risk.
- Always build signed (`-allowProvisioningUpdates`). Tests: `cd HITListCore && swift test`; app tests:
  `xcodebuild test -project HITList.xcodeproj -scheme HITList -destination 'platform=macOS'
  -allowProvisioningUpdates` and `-destination 'platform=iOS Simulator,name=iPhone 17'`.
- Read app logs with `/usr/bin/log show --info --last 5m --predicate 'subsystem == "com.trammells.hitlist"'`
  (`log` alone is a zsh builtin and prints nothing; `--info` is required). Categories: sync, storage, dedupe.
- Mac Release build for real-data verification: `-configuration Release -destination 'platform=macOS'`,
  launch the product from DerivedData. The real Mac store is
  `~/Library/Group Containers/UC8N98H3RT.com.trammells.hitlist/HITList.store`. Copy it before any
  destructive test. CloudKit mirroring state lives in the store's `ANSCKEVENT` table (type 0 setup,
  1 import, 2 export; ZSUCCEEDED, ZERRORCODE) and `ANSCKRECORDMETADATA` (one row per mirrored record).
- CloudKit.framework is linked explicitly on purpose (macOS 26 sandbox bug);
  `CloudSyncMonitor.refreshAccountStatus` is a real CKContainer call for the same reason. Keep both.
- Production CloudKit schema is additive-only; this task must not change any @Model (rules at the top
  of `SchemaVersions.swift`). `SchemaTests` pins entity hashes and fails if you do.
- `scripts/release.sh` uploads to App Store Connect: never run it, never edit it.
- `BackupService.swift` (home-server backup) is a deliberate unused design relic; leave it, don't
  surface it in UI.
- Commit per sub-item, messages ending in `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  Do not push, do not open a PR, do not merge.
- George reads instructions only in chat. Anything they must do goes in your final message with exact
  commands or click paths. Write no documents besides updating ROADMAP.md's item 5 status row.

## Task

Implement item 5 in four commits with tests. Files you own: `HITList/Services/CloudSyncMonitor.swift`,
`HITList/Views/SettingsView.swift`, `HITList/Views/SidebarView.swift` (small footer only),
`HITList/Models/ModelContainerFactory.swift`, `HITList/HITListApp.swift`, new files under
`HITList/Services` and `HITList/Support`, `HITListTests`, and `project.yml` only for the
`UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace` Info.plist keys if you use them.

### A. Sync state model and readable status (commit 1)
- Make `CloudSyncMonitor` the single source of truth for a `SyncState` enum: `.notSignedIn`,
  `.restricted`, `.offline`, `.syncing`, `.synced(Date)`, `.error(String, Date)`, `.localOnly(reason)`
  (when `ModelContainerFactory.isCloudKitEnabled == false`). Derive it from `CKContainer.accountStatus`
  (refresh on `.CKAccountChanged` and at start), `NWPathMonitor` reachability, and
  `NSPersistentCloudKitContainer.eventChangedNotification` events (started with no end = syncing; last
  succeeded export/import = synced; failed = error, keeping the `CKError` code and `localizedDescription`).
- Human text: "Synced 2 min ago" (relative, refreshes at least every minute while visible), "Syncing…",
  "Offline, changes will sync later", "Not signed in to iCloud", "iCloud restricted",
  "Sync paused: <short reason>". Pure function `SyncState.summary`, unit-tested.
- Settings → iCloud Sync: one status line plus a "Details" disclosure (account status, last import,
  last export, raw last error, store path). Keep the `.fixedSize(horizontal: false, vertical: true)`
  pattern; `LabeledContent` misbehaves in this sheet.
- Sidebar footer: one-line `Theme.secondaryText` status, shown only when not `.synced`; tap opens
  Settings. Quiet and slate.

### B. Account change handling (commit 2)
- On iCloud account change or sign-out, NSPersistentCloudKitContainer resets the local mirror and the
  list goes empty. Detect it (account status transitions plus `.CKAccountChanged`) and show a banner
  added at `ContentView` level, not by rewriting list views: "Signed out of iCloud. Your tasks are safe
  in iCloud and come back when you sign in." Never delete anything yourself on account change. Never
  call `ModelContainer.deleteAllData()` or delete objects through a context as part of any reset:
  deletions would mirror to CloudKit and wipe the user's data on every device.
- Log transitions under category "sync".

### C. Reset local cache and re-download (commit 3)
- Settings → iCloud Sync → "Reset local cache and re-download…" with a confirmation dialog saying data
  stays in iCloud and will be re-downloaded. Set the `AppGroup.defaults` flag
  `resetLocalStoreOnNextLaunch`; on next launch in `ModelContainerFactory.make()`, BEFORE opening the
  container, move the store files (`HITList.store`, `-wal`, `-shm`, `.HITList_SUPPORT`,
  `HITList_ckAssets`; reuse `moveStore`'s list) into `<group container>/Trash/<timestamp>/`, keep the
  last 2 trashed copies, clear the flag, log it. CloudKit then re-imports.
- Live part: after setting the flag, relaunch where the platform allows (macOS: open a new instance
  via `NSWorkspace.shared.openApplication(at:)` then `NSApplication.shared.terminate`, or quit with an
  alert telling the user to reopen; iOS: "Quit and reopen HITList to finish"). Pick the simplest
  approach you verify works; document it in a comment.
- Verify on the Mac with real data: record task/project/filter counts and the `ANSCKRECORDMETADATA`
  row count before; run the reset; confirm the store is re-created and all records return with the
  same counts; confirm no delete events were exported (no ANSCKEVENT type 2 before the first import
  after reset; CloudKit dashboard record count unchanged).
- Test: trash-and-recreate on a temp directory (creates the trash folder, moves all sidecars,
  rotates to 2 copies).

### D. Automatic local JSON backups (commit 4)
- Reuse `SnapshotBuilder` and the existing export JSON format. Once a day (on scene activation when
  the last backup is older than 24 h) write `HITList-<yyyy-MM-dd>.json` into `URL.documentsDirectory`,
  keep the newest 14, store `backup.lastLocalAt` in `AppGroup.defaults`. No new entitlements. iOS: add
  `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` via `project.yml` so Files shows the
  folder. macOS: "Show backups in Finder" button (`NSWorkspace.shared.activateFileViewerSelecting`).
  Settings shows "Last backup: <relative>" and "Back up now". Restore stays the existing Import JSON flow.
- Test: rotation keeps 14, filenames sort by date, skip when the last backup is under 24 h old.

### Finish
- All tests pass (`swift test` in HITListCore; `HITListTests` on macOS and the iPhone 17 simulator).
  Mac Release build launches against real data and shows "Synced … ago". Update ROADMAP.md item 5 to
  "done <date>".
- Final message: what changed per commit, test counts, how you verified the reset on the Mac (record
  counts before/after, log lines), the relaunch approach chosen, and any step George must do with exact
  commands or click paths. Mention the branch name.
