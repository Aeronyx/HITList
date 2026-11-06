# Brief 32: subtasks and a real task editor (branch `subtasks-editor`, effort xhigh)

Read `briefs/COMMON.md` first, then the header of `HITList/Models/SchemaVersions.swift` (schema rules).
Two other sessions run at the same time: 31 (quick-add parser, `QuickAddPopout`'s suggestion row,
`QuickAddContext`, `TaskActions` roll-over) and 33 (haptics, toast, add buttons, fonts, Mac reopen). Do not
touch their files; your `QuickAddPopout` edits are limited to the "+" option bar and the subtask lines.

George's words, from the 0.4.0 (13) feedback on 2026-11-03:

> Implement Subtasks (nested tasks, only one level deep) that function sort of like a "checklist" for a
> single task. Allow adding them via the "+" in the "Add task" popout or by editing a task after the fact.

> The task edit screen should have a "Confirm" button (ideally the same as the "Confirm add task" button)
> and edits should land as soon as I press it; I shouldn't have to tap twice to confirm an edit and close
> the task. This button should do both.

> Also, the task edit screen looks pretty lazy in general. I've attached a pair of screenshots showing
> HITList next to a mockup of a superior task editing screen. No need to copy it directly if you don't
> want, but you get the idea. Please make a better task editing system.

The mockup (Todoist's task view, dark): a sheet with a close "×" top-left and "…" top-right; a card holding
the title row (check circle + large title), a Group row (tray icon "Inbox"), a hairline, a date row (green
calendar icon "Today"); under the card a row of outlined pills "Description", "Priority", "Reminders"
(scrolling horizontally); then a "Sub-tasks" section header with a chevron and a "+", an "Add Sub-task"
row in its own rounded card; a "Comment" field pinned at the bottom. Ours today: title at the top with "…"
and "×", "Add description", a wrapped row of chips (Yesterday, Priority, Inbox, Labels, Reminder, Repeat),
"Created …", empty space. Make ours read like the mockup in HITList's own slate design system
(`HITList/Support/DesignSystem/README.md`): cards from `Theme.surface`, `HITType` roles, `HITChip`,
existing pickers (`PopoutPickers`, `Pickers/*`), the Mac's in-window panel keeps the same structure.

## Items (one commit each, failing test first for logic)

1. **Schema V3**: `TaskItem.parent: TaskItem?` (optional to-one, `@Relationship(deleteRule: .cascade,
   inverse: \TaskItem.subtasks)` on the parent side is not allowed to be non-optional; follow the file's
   rules: both sides optional, parent nullify, children cascade from the parent) and `subtasks: [TaskItem]?`.
   Freeze V2's stored properties as `SchemaV2Models.swift` the way `SchemaV1Models.swift` freezes V1, add the
   lightweight stage, extend `SchemaTests` (V3 only adds the relationship; V1 and V2 hashes unchanged).
   Snapshot/backup (`Snapshot.swift`, `SnapshotBuilder.swift`): parent id per task so backups round-trip.
   `Deduplicator`: subtasks follow their parent when duplicates merge. Do NOT deploy the CloudKit schema
   and do not open the real store: the report must say in bold that George must deploy
   Development → Production in the CloudKit dashboard before the next release, and how the fields reach
   Development (the SchemaVersions header's `-seedSampleData` run with `HITLIST_STORE_SUFFIX=schema`; run it
   yourself with the Debug Mac build so Development already has the field when George looks).
2. **Rules** (`TaskActions`, `TaskOrdering`, `FilterQuery`): one level only (a subtask cannot get a parent
   that has a parent; a task with subtasks cannot become a subtask). Subtasks are never listed as rows of
   their own in Inbox, Today, Upcoming, Browse, saved filters or Flipboard; they live inside the parent.
   Completing the parent completes its open subtasks (undo restores them); completing the last subtask
   does not complete the parent (Todoist's rule; George can ask otherwise). A repeating parent rolling over
   resets its subtasks to open. Deleting the parent deletes its subtasks (cascade). Reminders: subtasks have
   none. Subtasks inherit the parent's Group; they have no date, priority or labels of their own in this
   version (title + done only: a checklist). Snapshot export/import preserves them.
3. **The task editor** (`TaskPopout.swift`, iPhone sheet and Mac panel): the layout above. Title row with
   the check circle; Group row; date row (with time) that opens the existing date card; pills for
   Description, Priority, Reminder, Labels, Repeat, Deadline, Location (filled when set, outlined when
   not; a set one shows its value); "Sub-tasks" section with progress ("2 of 5"), each subtask a check
   circle + title (inline rename on tap, swipe/menu to delete, drag to reorder via `sortOrder`), an "Add
   Sub-task" row that becomes a text field, Return adds and keeps the field open, empty Return closes it.
   Drop "Created …" from the body (move it to the "…" menu or the bottom in `HITType.caption`). The
   **Confirm** button: the same filled pill as the quick-add card's confirm (see `QuickAddPopout.footer`,
   `canAdd`), bottom-right on the iPhone, the panel's footer on the Mac; one tap saves everything pending
   (title, description, the open subtask field's text) and closes the editor. Esc / "×" closes without
   saving unsaved typing, but field edits that already landed (chips) stay as today. Return in the title
   confirms. Mac: ⌘Return confirms.
4. **Quick-add card** (`QuickAddPopout.swift` option bar, `QuickAddDraft.swift`): a "Subtasks" option in
   the "+" bar (icon `checklist`) reveals a list of subtask lines under the description: a text field per
   line, Return adds the next, Backspace on an empty line removes it. Saved with the task; the sticky draft
   (`QuickAddDraftStore`) stores them. Session 31 is editing `restoredDraft` for Groups: add your subtask
   lines as a new Codable field and keep that function's shape.
5. **Rows** (`TaskRow.swift`): a parent with subtasks shows "2/5" with a small `checklist` glyph in its
   meta line (`MetaItem`), nothing when it has none. Keep `ListMetrics` as they are; session 33 may change
   the font tokens in `HITTokens.swift`, which you must not touch.

## Ownership
`HITList/Models/Models.swift`, `SchemaVersions.swift`, new `SchemaV2Models.swift`, `SchemaTests`;
`HITList/Services/TaskActions.swift` (everything except the roll-over's time handling, which session 31
owns: call its `RecurrenceRule` helper if it exists by the time you merge, else leave a TODO);
`Deduplicator.swift`; `Snapshot.swift` / `SnapshotBuilder.swift` + tests; `TaskPopout.swift` and new files
under `Views/Popouts/Editor/`; `QuickAddPopout.swift` (option bar + subtask lines only), `QuickAddDraft.swift`
(subtask lines only); `TaskRow.swift` (meta line only); `TaskOrdering.swift` (subtask exclusion only; session
31 edits `priorityThenDue`, so put yours in a separate function); `FilterQuery.swift` (exclusion only);
`PopoutTests`, `TaskActionsTests`, new `SubtaskTests`; `project.yml` only to add files, then `xcodegen generate`;
ROADMAP row "Subtasks and the task editor (brief 32)".

## Done
All three suites green; iPhone 17 simulator: add "Pack for trip" with three subtasks from the card, open
it, tick two, see "2/3" on the row, Confirm closes in one tap; Mac: the panel shows the same sections
(run the Mac app with the in-memory demo hook as earlier sessions did; note what you could not click).
CHANGELOG: do not edit; list user-facing changes in the report for Fable to write.
