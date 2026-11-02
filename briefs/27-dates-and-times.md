# Brief 27: Dates, times and repeats the way George reads them

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md`, then `HITListCore/Sources/HITListCore/DateExpression.swift`,
`RecurrenceRule.swift`, the date and time assembly in `QuickAddParser.swift` (where `matchTime` and the
recurrence are combined into `QuickAddResult.dueDate`), `HITList/Services/TaskActions.swift` (completing a
recurring task advances it) and the tests in `HITListCore/Tests/HITListCoreTests/` (DateExpressionTests,
QuickAddParserTests, RecurrenceRuleTests) and `HITListTests/TaskActionsTests.swift`.

## George's decisions (2026-11-02), each a rule to implement with tests
1. **Monthly (and yearly) repeats keep their original day.** "every month" created on the 31st falls on
   Jan 31, Feb 28 (or 29), Mar 31, not Mar 28. Keep the anchor day in the stored rule string compatibly:
   a rule without it behaves as today, a build before this one ignores the extra part (recurrence is a
   string field; no schema change, Production is additive-only). `nextOccurrence`/`nextDueDate` use the
   anchor; completing a task on Feb 28 still lands on Mar 31. Yearly: Feb 29 → Feb 28 in a common year →
   Feb 29 again.
2. **A repeating task typed at a time already past today starts at its next occurrence.** "Standup every
   weekday 9am" typed at 2 pm is due tomorrow 9 am, not today overdue; "every day 8pm" typed at 7 pm is
   today. An explicit past date the user typed ("yesterday", "oct 3") is kept as typed. A current test
   pins the old behaviour; change it.
3. **Times are 24-hour unless the user says otherwise.** "at 5" is 05:00, "at 17" is 17:00, "5:30" is
   05:30, "tom 13" is tomorrow 13:00, "5pm"/"5p"/"5 pm" is 17:00, "noon"/"midnight" as now. Remove the
   "1–6 means PM" heuristic in `parseClock`. A bare hour (0–23) directly after a date word ("tom 13",
   "friday 9") or after "at" is a time; a bare number elsewhere ("Buy 3 apples") is not. Update every
   test and example that assumed the old reading, and the help text that shows examples (grep for
   "5pm", "at 5", "9am" in `HITList/Views` help and placeholder strings; change only wording, not layout).

## Files you own
`HITListCore/Sources/HITListCore/DateExpression.swift`, `RecurrenceRule.swift`, the date/time/recurrence
assembly in `QuickAddParser.swift` (session 28 adds a *new* file beside it for token disabling and does
not edit `QuickAddParser.swift`; keep your edits to the date/time/recurrence logic), `TaskActions.swift`'s
recurrence advancement, the core tests named above, `HITListTests/TaskActionsTests.swift`,
`QuickAddCreateTests.swift`, help/placeholder strings, one ROADMAP row. Not yours: anything else in `Views/`,
`Models.swift`, the popouts, the lists.

## Work
Tests first for each rule, then the change; `scripts/test.sh core macos` after each commit, `ios` before
the last. Commit per rule. Report: the rules as implemented with the exact strings you tested, anything
ambiguous you decided (say which way), test counts before and after, the branch name.
