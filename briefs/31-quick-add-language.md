# Brief 31: quick-add language, repeat times, creation order (branch `quick-add-language`, effort High)

Read `briefs/COMMON.md` first. Work only in the files listed under Ownership. Another session (32) is
rebuilding the task editor and adding subtasks in `TaskPopout.swift`, `QuickAddDraft.swift`, `Models.swift`;
a third (33) is doing haptics, the toast and the add buttons. Do not touch their files.

George's words, from the 0.4.0 (13) feedback on 2026-11-03:

> Add time phrases to quickadd, such as "in two hours", "in three days", "in 10 minutes", etc. and other
> relevant logic. Also, Reminders have weird quickadd logic right now; "!0mb" means "!" (I want to set a
> reminder, but means nothing by itself), and "Xmb"/"Xhb"/"Xdb" (X minutes/hours/days before). Clean it up
> and only highlight it when it's valid so the user isn't confused.

> Some tasks fly out of order after being added; tasks should be listed chronologically (by time of
> creation) if Priority and Date are equal and the filters aren't messing with anything else.

> The tiny text popups below the task name bar when trying to add a task, which suggest spelling
> corrections and quickadd dates, must be removed. It is silly and poor UI design.

Decisions George made on the review-30 questions: store the repeat's time in the rule text (fixes the
2 AM spring-forward drift); "tomorrow 3" / "tom 3" means tomorrow 3:00 AM (keep); "next mon" on a Sunday
means tomorrow (keep, already tested); the Group-renamed-while-a-card-was-saved case: fix if needed.

## Items (one commit each, failing test first where there is logic)

1. **Relative time phrases** in `DateExpression` / `QuickAddParser`: `in 10 minutes`, `in 10 min`, `in 2
   hours`, `in two hours`, `in an hour`, `in half an hour`, `in 3 days`, `in a week`, `in 2 weeks`,
   `in a month`, number words one–twelve, with and without "in" where unambiguous only ("10 minutes" alone
   is a title). Minutes and hours set `hasDueTime` from `now` (round to the minute; no seconds); days and
   weeks keep the time of day of the current due time if one was typed, else no time. Highlight the whole
   phrase as one `.date` token; tapping it disables it like any other token (`QuickAddParser+Disabled`).
   The same phrases in `DateExpressionParser` for filters where they already parse `today`/`tomorrow`
   (`due before in 3 days` is odd; support `in N days` as a date only if it is free; do not bend the filter
   grammar). Tests in `HITListCore/Tests` with a fixed `now` and calendar, including "in 2 hours" at
   23:30 crossing midnight and "in 1 day" on the spring-forward night (New York).
2. **Reminder syntax clean-up** (`ReminderOffset` in `QuickAddParser.swift`): valid forms are `!Nm`,
   `!Nmb`, `!Nh`, `!Nhb`, `!Nd`, `!Ndb` (N ≥ 1), `!0` and `!at` (at the due time). A bare `!`, `!0mb`,
   `!m`, `!xyz` are not reminders: no token, no highlight, the text stays in the title. A reminder token
   only counts (and is only highlighted) when the task has a due time to be relative to, or when the
   phrase sets one; `!1hb` on an undated task stays plain text. The chips (`ReminderOffset.token`) keep
   writing `!15mb` / `!1hb` / `!1db` / `!at`. Update the quick-add help text wherever the syntax is listed
   (`grep -rn '!15mb' HITList HITListCore`). Tests for each form, valid and invalid.
3. **Repeat keeps its time** (`RecurrenceRule`, `TaskActions.toggleCompletion` roll-over): encode the due
   time of day in the rule (a fifth part, e.g. `daily;1;;;02:30`, additive so old rules still decode) and
   when rolling to the next occurrence rebuild the time from the rule's hour and minute in the current
   calendar, not by adding seconds. Turn the expected failure in `RealCalendarTests` (2:00–2:59 AM on the
   spring-forward night) into a pass. `TaskActions.setRecurrence` and the time setters in the editor
   must keep the rule's time in step (the editor is session 32's file: expose one `RecurrenceRule`
   helper, e.g. `withTime(hour:minute:)`, and have `TaskActions` apply it; session 32 will call it).
4. **Creation order**: `TaskOrdering.priorityThenDue` breaks ties on `filterCreatedDate` ascending (older
   first) before the title. Check every list that sorts (`TaskListView`, `InboxView`, `UpcomingView`,
   `FilterQuery.defaultSort`) uses it or the same rule; the "fly out of order after being added" George
   sees comes from the title tiebreak reordering as they type. Tests.
5. **Remove the suggestion row** in `QuickAddPopout.swift` (`suggestionRow`, `autofill`, `SuggestionStyle`,
   the `engine` rebuilds if nothing else uses them). Keep `AutocompleteEngine` in HITListCore (tests use it)
   unless it is dead; if dead in the app, say so in the report and leave it.
6. **Group renamed while a card was saved** (`QuickAddContext.swift`, `QuickAddDraftStore.restoredDraft`):
   store the Group's `id` beside its name; on restore, resolve by id first, then by name; if neither exists,
   drop the Group rather than recreate it. Test with an in-memory container (`ModelContainerFactory.preview()`).

## Ownership
`HITListCore/Sources/HITListCore/DateExpression.swift`, `QuickAddParser.swift`, `QuickAddParser+Disabled.swift`,
`RecurrenceRule.swift`, `TaskOrdering.swift`, `FilterQuery.swift` (only `defaultSort`), their tests;
`HITList/Services/TaskActions.swift` (roll-over and `setRecurrence` only); `HITList/Views/Popouts/QuickAddPopout.swift`
(only the suggestion row and its helpers); `HITList/Views/Popouts/QuickAddContext.swift`; the restore path in
`QuickAddDraft.swift` (`restoredDraft` only; session 32 adds subtask lines elsewhere in that file); the
`FilterSyntaxHelpView` / quick-add help text; `PopoutTests` and `QuickAddDraftTests` where they cover these;
ROADMAP row "Quick-add time phrases, reminder syntax, repeat time, creation order (brief 31)".

## Done
`scripts/test.sh core`, `scripts/test.sh macos`, `scripts/test.sh ios` green; typing "Call mum in 2 hours
!15mb" in the iPhone 17 simulator shows both highlights and a Date chip two hours from now; "Fix sink !"
shows no reminder highlight; two tasks added seconds apart with the same priority and date stay in the
order they were added.
