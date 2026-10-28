# Brief: Todoist-parity filter language + filter editor

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first.

## Files you own
`HITListCore/Sources/HITListCore/FilterQuery.swift`, `DateExpression.swift`, `AutocompleteEngine.swift`
(filter-side only), `FilterableTask.swift` (additive only), their tests under
`HITListCore/Tests/HITListCoreTests/`, `HITList/Views/FilterEditorView.swift`, new files under
`HITList/Views/Filters/`, new test files in `HITListTests/`. `TaskItem: FilterableTask` lives in
`HITList/Models/Models.swift`; you may add computed properties to that extension ONLY (no stored
properties, no schema change). Nothing else.

## Goal
Robust priority/date filtering is one of HITList's three founding goals. Bring the query language to
parity with Todoist's filter reference (https://todoist.com/help/articles/introduction-to-filters-V98wIH)
wherever it makes sense for a single-user app, keep every existing query working, and make the editor
a pleasure: live preview, inline errors, help, autocomplete.

## Task, four commits
1. **Audit + language.** Read the current tokenizer/parser/evaluator, write the gap list against
   Todoist's reference in your final message, then implement (all case-insensitive, with the
   existing `&`/`,` `|` `!` and parentheses):
   - Dates: `due before: <date>`, `due after: <date>`, `due: <date>`, `date before/after`, `no date`,
     `!no date`, `7 days`, `-3 days`, `next 7 days`, `due before: +7 days`, `this weekend`,
     `next weekend`, weekday names (`due: monday`), month names, ISO and `10/31` dates, `today..friday`
     ranges if cheap. `overdue`, `today`, `tomorrow`, `yesterday`, `recurring`, `no time`, `has time`.
   - `created before/after: <date>`, `created: today`.
   - Priority: `p1`..`p4`, `priority >= 2`, `no priority` (= p4).
   - Projects/labels: `#Project`, `#"Two words"`, `@label`, `no project`, `no labels`, wildcards
     `#Work*`, `@home*`, `!#Inbox`.
   - Text: `search: groceries` (title + notes, substring, case-insensitive), `search: "exact phrase"`.
   - `all`, `completed`, `!completed` (default queries exclude completed unless mentioned, as today).
   Produce structured errors with ranges (`FilterQueryError` already has position; add `length` and a
   human message like "Unknown keyword 'tomorow'. Did you mean 'tomorrow'?").
   Add `FilterQuery.describe(_:) -> String` that renders a parsed query back as readable English
   ("Priority 1 or 2, due today or overdue") for the editor's preview. Keep evaluation pure and
   deterministic (`now` and `calendar` injected). 60+ new core tests; every example in Todoist's
   reference that applies should be a test.
2. **Autocomplete for filters.** `AutocompleteEngine.filterSuggestions(text:cursor:projects:labels:)`
   returning keywords, operators, `#`/`@` names and date words appropriate to the cursor position,
   with ranges to replace. Tests.
3. **Filter editor.** Rework `FilterEditorView` (slate theme, both platforms): name, colour, query
   field with monospaced font and inline error underline/message, a live "N matching tasks" count
   and the English description, a chip row of suggestions from (2), a "Syntax help" popover/sheet
   that lists every keyword with one example each (generated from a single table in core so it can't
   drift), and 6 one-tap templates (Focus, This week, Someday, Waiting, Quick wins = `p3 | p4 & no
   date`, Overdue). Validation blocks Save with a clear message. Keep the existing save/delete flow.
4. **Polish + ROADMAP.** Add a "Filter language" row under a new "Core" heading in ROADMAP.md's
   status table marked done, and append to the Decisions log one line on which Todoist features were
   deliberately skipped (collaboration, assigned, subtask, sections) and why.

## Verify
`swift test` (expect 100+ core tests), `HITListTests` on macOS, signed simulator and Mac builds;
exercise the editor by hand on the simulator with several queries including an invalid one. Report
per COMMON.md, including the gap list and what you skipped.
