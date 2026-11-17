# 156: the data-safety review's findings, fixed (code)

Round 32's review 151 (and parts of 147, 152 and 155) found ways the app deletes or drops more than a person meant.
Fix the ones listed, each with a test written first and seen to fail. The reports, with places and steps, are in
the notes folder: `round-32/151-data-safety-review/REPORT.md`, `147-engine-live-review/REPORT.md`,
`152-crash-concurrency-review/REPORT.md`, `155-privacy-security-review/REPORT.md`. Read 151's whole.

**Yours**: `HITList/Services/Deduplicator.swift`, `LocalBackup.swift`, `SnapshotBuilder.swift`,
`HITList/Services/Import/`, `HITList/Views/Import/`, `HITList/Views/ProjectEditorView.swift`,
`FilterEditorView.swift`, `HITList/Views/Groups/GroupDeletion.swift`, `HITList/Views/Settings/DataSettingsGroups.swift`,
core's `TodoistMapping.swift`, `TodoistReader.swift` and their tests; and **only the label-deletion code** in
`HITList/Views/Tabs/BrowseView.swift` and `HITList/Views/SidebarView.swift` (agent 158 is rewriting those two files'
queries and counts at the same time: keep your hunks small and apart). Tests in `HITListTests/` and core's tests.
**Not yours**: anything under `HITList/Services/SyncEngine/`, `HITList/Views/Popouts/`, `TaskActions.swift`, the list
views (`TaskListView`, `InboxView`, `UpcomingView`, `Search/`), `HITList/Views/Settings/ICloudSettingsGroups.swift`.

1. **A label is deleted by one swipe, with no question and no undo; Flipboard's own label can be deleted** (151 A1).
   Ask first when the label is on any task, as a Group with tasks does (`GroupDeletion`), and never offer Delete for
   the label whose id is `Flipboard.labelID`.
2. **The merge by name deletes what a person made on purpose** (151 A2; 147 F2 and F8).
   - The three editors refuse a name already used by another item of the same kind (trimmed, case-insensitive), with
     one plain line under the field; renaming an item to its own name is fine.
   - Filters merge by name only when their queries are equal.
   - **On HITList's own engine (`ModelContainerFactory.isOwnEngineEnabled`) there is no merge by name of Groups,
     labels and filters at all**: the engine names a record by its `id`, seeds carry stable ids, and a deletion made
     by a merge becomes a marker that deletes the item on every device. The profile merge, the sub-task repair and
     the merge of rows that share an `id` stay. `SyncEngine.mergeSharedIDs` calls `Deduplicator.run`: make the engine's
     behaviour one decision inside `Deduplicator` (a parameter with the engine's answer as its default), not a check
     at each call site, and do not edit `SyncEngine.swift`.
3. **A Todoist import drops a second task of the same title in the same project** (151 A3), and **a stopped import
   says nothing was written and cannot be undone** (151 B5): the receipt after each batch, a rollback in the catch,
   and words that say how many were written and that Undo removes them.
4. **A description has no limit** (151 A4). `TaskLimits.notesCharacters` and `clampedNotes` are on master: apply them in
   the Todoist import and in Import JSON (the editor's draft is agent 157's).
5. **Import JSON brings back everything deleted since the backup, without asking** (151 B8): count what the file
   holds that is not on this device and ask first, in a person's words.
6. **A crafted Todoist ZIP exhausts memory** (155 finding 5): skip names that are not `.csv` before inflating, cap the
   inflated total, refuse an offset already seen.
7. **The daily backup runs on the main thread** (152 finding 5) and **a failed one is only logged** (151 C14): build,
   encode and write off the main actor on a context of its own; a failure goes to the sync log as an error line and
   Settings → Backups says "Last backup failed" with the words until one succeeds. Its log line names the path
   from `/Library/` on, not the user's home folder (155 finding 8).
8. **Backups leave out the profile** (151 C12): say so in the backups' footer in one line; do not change the format.
9. **The Group, label and filter editors save into the model they opened with, which a merge may have deleted**
   (152 finding 2): keep the id; on Save fetch by id and write into what comes back; if nothing comes back, close
   with one line saying it is no longer there.

Proof: core `swift test`; the Mac's hosted tests for the classes you touched and the whole of `HITListTests` once at
the end (`xcodebuild test -project HITList.xcodeproj -scheme HITList -destination 'platform=macOS'
-allowProvisioningUpdates -derivedDataPath build.noindex/156`); for the label question and the editors' refusal, a
look at the running Debug Mac app on a side store (`HITLIST_STORE_SUFFIX=p156 -disableCloudKit YES
-ApplePersistenceIgnoreState YES -seedDemoData`, `scripts/window-shot.sh`), pictures in your notes folder. Words a
person reads are plain and short; text keeps 12 pt from a card's edge.
