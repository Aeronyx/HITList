# 147: what breaks when a released build runs the engine on the real store (read-only review)

`dev/SYNC-ENGINE.md` section 14, stage 5. The next release lets a released build run HITList's own sync engine on
the real store (`HITList.store`): George's Mac and iPhone first, through a row only he is told how to reach; everyone
else stays on SwiftData's mirror until a later release. Until now the engine has only ever run in Debug builds on
side stores, and every line of the app outside `HITList/Services/SyncEngine/` was written for the mirror.

**Find everything that will be wrong when `SyncEngineSwitch.current == .own` on the real store, in a release build,
on iPhone, iPad and Mac.** You are reviewing the code that exists, not the supervisor's plan.

Read first: `dev/SYNC-ENGINE.md` whole (sections 4, 8, 10, 11 most); `HITList/Services/SyncEngine/SyncEngine.swift`,
`SyncEngine+Move.swift`, `SyncEngineSwitch.swift`, `SyncEngineHost.swift`, `SyncSaveHints.swift`,
`SyncDeletionLog.swift`; `HITList/HITListApp.swift`; `HITList/Models/ModelContainerFactory.swift`.

Angles, each to be answered with findings or with "looked, nothing":

1. **Every reader of the mirror's state.** `ModelContainerFactory.isCloudKitEnabled`, `CloudSyncMonitor`,
   `SyncState`, `SyncSteadiness`, `SyncSessionGate`, `SyncRecordCheck`, `SyncAudit`, `SyncRepair`, Check iCloud… and
   its repairs, the watchdog, `LocalCacheReset`, the widgets' finish line. For each: what it does on the engine today
   (stands down, answers from the engine, or keeps talking to the mirror's zone in the tasks' container, which on the
   engine is stale by design). Anything that reads or repairs the mirror's zone while the engine syncs is a finding.
2. **Who writes the store outside the app's main process, or outside its main context.** The widget extension's
   intents (on a Mac they run in the extension), the share extension, App Intents and Shortcuts, the MCP helper
   (`HITListMCP`, `ClaudeHelperBridge`), Spotlight, background tasks, the Todoist import, restore from a backup,
   `Deduplicator`, the day anchoring, Reset local cache. For each: is a change found (the engine compares at a start
   and when the app comes forward, and otherwise only hears saves made in its own process); is a **deletion** noted
   (only at `ModelContext.willSave` in the app's process; a deletion nobody noted comes back from iCloud); how long
   can a change wait unsent; does anything use a batch delete (`delete(model:)`), which bypasses the note. Is the
   save observer on every context of the container, or only the main one?
3. **The engine's own deletions seen as a person's, and the reverse.** `Deduplicator`'s merges delete rows: on the
   engine they become markers that delete the row on every device. Trace what two devices do when each merges the
   same pair, and when each keeps a different one of the pair.
4. **Life cycle.** Launch order in `HITListApp.init`; `SyncAppDelegate` (pushes, background refresh, termination);
   scene phases; an iPhone app launched in the background by a push, with the phone locked (file protection: can the
   store and the ledger be opened then, and what happens if not); the app killed in the middle of a send.
5. **The account.** `AccountSwitch` and `AccountWatch` (mirror era) and the brain's own handling of a sign-out
   (`SyncHost.willRemoveLocalData`, a backup, then what was synced leaves the device): two owners. Say exactly what
   each does today on the engine, in what order they could run, and propose the one order.
6. **The move** (`SyncEngine+Move.swift`) on the real store: iPhone and iPad say "quit and reopen" (what if the app
   is only sent to the background and brought back; the mirror keeps running in this process while the preference
   already says `own`); the Mac relaunches itself. A move while the mirror still has changes it has not exported. A
   move made on one device and not the other (the two do not see each other's changes until both moved: is the
   person told, and where). **The way back**: when the store is reopened with the mirror, does the mirror export
   what changed while the store was open without it? Read what is known of SwiftData's and Core Data's persistent
   history with `cloudKitDatabase: .none`; say what is known, what is not, and how to find out.
7. **Settings → iCloud on the engine** (`HITList/Views/Settings/`): every row, button and sheet a person can reach
   while the engine syncs; which belong to the mirror and must hide or change; what Reset local cache does on the
   engine; what the Help pages say about sync that is no longer true on the engine.
8. **Other containers and features that lean on the mirror**: Shared Tasks (`HITList/Services/Sharing/`), the
   profile, backups (`LocalBackup`), export and import, Spotlight, reminders, the calendar, widgets, the companion.
9. **Words**: every string a person on the engine will read ("iCloud's mirror", "HITList's own", hold texts, the
   bolt's captions). A friend has never heard of an engine; say which words they would not understand.

Write `FINDINGS.md` in your notes folder, and report as the Round 32 block of `dev/briefs/COMMON.md` says.
