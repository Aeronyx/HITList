# Brief 48: "!15m" means 15 minutes from now (branch `reminder-language`, effort xhigh)

Read `briefs/COMMON.md` (Round 11 block) and `briefs/HIG-NOTES.md` first. Five sessions run at the same time. You
are the only session changing the data model this round, and you are merged last.

George's words, 2026-11-05:

> "!15mb" naturally requires a time before it would get highlighted, but "!15m" would not, as it just means 15
> minutes from now. For "!" quickadd commands like these reminders, have the highlight logic function slightly
> differently so it only checks/adds a highlight after the user presses space instead of while they're typing it.

Today `!15m` and `!15mb` both mean "15 minutes before the due time" (the "b" is optional;
`QuickAddParser.swift` reminder grammar). The model only stores `reminderOffsetMinutes` (before the due time), so "in
15 minutes" needs an absolute reminder time.

## Items (one commit each, failing test first)
1. **Grammar** (HITListCore): `!15m`, `!2h`, `!1d` (and `!90m`, `!1h30m` if cheap) = a reminder at now + that long,
   with or without a due date or time; `!15mb`, `!2hb`, `!1db` = before the due time (needs a time, as now); `!at` /
   `!0` = at the due time. A later reminder phrase of the same kind overrides an earlier one (37's superseded rule);
   one "from now" and one "before" may coexist. Tests across midnight and DST.
2. **Highlight after space**: a "!" phrase lights up and counts only once it is complete: followed by whitespace,
   or at Confirm (the final parse treats the end of the text as complete, so "Call mom !15m" + Confirm still sets the
   reminder). While the caret is still inside or right after a "!" word being typed, it stays plain. Implement it as a
   parse option the draft passes (`live` vs `final`), not as a field trick.
3. **Model: schema V5** (`Models.swift`, `SchemaVersions.swift`, new `SchemaV4Models.swift` freezing V4,
   `SchemaTests` with a `testV5OnlyAddsReminderDate`): `TaskItem.reminderDate: Date?` (optional, additive). Push it to
   CloudKit Development with the Debug Mac run in the `SchemaVersions.swift` header (own store suffix, CloudKit on,
   never the real store), confirm "exporting succeeded", quit the Debug app. George deploys before the release.
4. **Notifications** (`NotificationScheduler`, `Services/Notifications/*`, `TaskActions` reminder paths): schedule
   `reminderDate` as its own notification (independent of the due-time reminder), cancel on complete/delete/edit,
   honour the account-switch clearing (42) and the Debug stand-down; a repeating task's "from now" reminder fires
   once (does not repeat); say so.
5. **Chips and editor**: the quick-add Reminder chip shows "In 15 min · 3:47 PM" for a from-now reminder and offers
   "In 15 minutes / In 1 hour / Later today…" beside the before-due offsets (`QuickAddPopout` Reminder chip region and
   the reminder picker); the editor's Reminder pill shows and edits it (`TaskPopout` Reminder pill region /
   `Editor/*`); the task row's meta line shows a small bell with the time.
6. **Everywhere data goes**: snapshot JSON/export/backups (`Snapshot`, `SnapshotBuilder`), restore, dedupe (keep
   the field when merging duplicates), the Claude tools' task JSON (report the one-line change to session 49 rather
   than editing `Services/Claude/*`), Siri's Add Task (it parses through the same parser: check "remind me in 15
   minutes" phrasing does nothing surprising).

## Ownership
HITListCore `QuickAddParser.swift` (+Disabled), `DateExpression.swift` if needed, `Snapshot*` + tests;
`Views/Popouts/QuickAddDraft.swift`; `Models/Models.swift`, `SchemaVersions.swift`, new `SchemaV4Models.swift`,
`ModelContainerFactory` model list only; `Services/NotificationScheduler.swift`, `Services/Notifications/*`,
`TaskActions.swift` (reminder parts), `SnapshotBuilder.swift`, `Deduplicator.swift` (field merge only);
`QuickAddPopout.swift` (Reminder chip region only), `PopoutPickers.swift` / `Pickers/*` (reminder picker),
`TaskPopout.swift` + `Editor/*` (Reminder pill region only), `TaskRow.swift` (meta bell only); tests `SchemaTests`,
`PopoutTests` (append), new `ReminderDateTests`; ROADMAP row "Reminders from now (brief 48)". Not yours:
`TokenHighlightField.swift` (47), `Services/Claude/*` (49), `PopoutHost.swift` (50).

## Done
All three suites green; Development schema push log lines; iPhone simulator screenshots: "Call mom !15m" plain while
typing, lit after a space with the chip "In 15 min · …"; "Call mom 5pm !15mb" lit; the editor pill; a delivered
notification in the simulator if you can make one fire (a test hook with a 1-minute reminder is fine).
