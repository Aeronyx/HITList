# 151: everything outside sync that can lose or corrupt a person's data (read-only review)

Before a real launch. Sync itself is reviewed by 147 and 148; yours is the rest of the path between a person's
finger and the store, and every way back from a disaster.

Read: `HITList/Models/` (the models, `SchemaVersions.swift`'s header, the migration plan,
`ModelContainerFactory.swift`), `HITList/Services/TaskActions.swift`, `Deduplicator.swift`, `LocalBackup.swift`,
`LocalCacheReset.swift`, `SnapshotBuilder.swift` and core's `Snapshot.swift` (the export and backup format),
`HITList/Services/Import/` (Todoist), `HITList/Services/Dates/` and core's `DayAnchor.swift`, `RecurrenceRule.swift`
and the completion roll-over, the editors' drafts (`HITList/Views/Popouts/`, `Flipboard/SwitchDraft.swift`), undo,
`HITList/Services/Share/` and core's `ShareOutbox.swift`, `WidgetOutbox.swift`, `HITList/Services/Intents/`.

Answer each with findings or "looked, nothing":

1. **A backup that cannot restore is no backup.** Does an export or a daily backup carry every stored field of every
   model (compare the snapshot's fields with the models', field by field, relationships included: a task's parent,
   its labels, its Switchboard, sub-tasks' order)? Does restore put back exactly that, with the same ids? What does
   restore do to what is on the device (replace, merge, duplicate), and what does it do to every other device
   through sync? A newer build's backup opened by an older build, and the reverse. A backup written while a save is
   half done. Where backups live, how many are kept, what prunes them, and whether a failed write is ever said.
2. **Migrations**: every stage is lightweight and additive; a store from each earlier schema version opens; what a
   failed migration leaves (the in-memory fallback: can a person lose what they then type? are they told plainly?).
3. **Destructive actions**: delete a task with sub-tasks, a Group with tasks in it, a label, a Switchboard, a
   filter; "delete completed"; bulk actions. Each: is there an undo or a confirmation, does the count said match the
   count deleted, what happens to the rows that pointed at it. Anything that deletes more than the words promise.
4. **The duplicate merges** (`Deduplicator`): by shared id and by name. Can two things a person made on purpose
   (two Groups of one name, two labels) be merged away? What happens to their tasks? Is anything ever merged that
   differs in a field the merge then drops?
5. **Dates**: a due date across time zones and daylight saving (the day anchoring at 10:00 UTC), a recurring task
   completed late, twice, or on two devices; a reminder's time against the due day; year boundaries. Only what can
   store a wrong value, not what merely shows one.
6. **Imports**: Todoist. A second import of the same archive (duplicates?), an archive with thousands of tasks, a
   malformed file, an import interrupted. Does an import ever touch what was already there?
7. **Editors and drafts**: an edit typed and not saved when the app goes to the background, is killed, or another
   device's change to the same task arrives; two windows on the Mac editing one task; quick-add's parser eating
   words a person meant as text.
8. **Other processes**: the widget's and the share extension's outboxes: an item put in while the app is not
   running; applied twice; lost if the app is deleted or the file is unreadable.
9. **Limits**: `TaskLimits`. A title or note of a megabyte pasted in; ten thousand sub-tasks; a label name of
   only spaces; empty titles.

Write `FINDINGS.md` in your notes folder, and report as the Round 32 block of `dev/briefs/COMMON.md` says.
