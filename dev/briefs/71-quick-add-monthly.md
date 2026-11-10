# Brief 71: quick add reads monthly and yearly repeats (session `quick-add-monthly`, effort high)

George, 2026-11-10, on 0.9.0 (20):

> Add more quickadd highlights, such as "every month on the 28th" and related phrases.

Read `dev/briefs/COMMON.md` (Round 16 block first), then `31-quick-add-language.md` and `37-highlight-merge-override.md`
for how phrases, highlights and overrides work. The grammar lives in `HITListCore`: `QuickAddParser.swift`
(+ `QuickAddParser+Disabled.swift`), `DateExpression.swift`, `RecurrenceRule.swift`. A highlight is the parser's range
for a phrase (`TokenHighlightField` draws it), so a phrase the parser reads lights up by itself in the quick-add card,
the editor's title (round 15) and the Flipboard's switch card.

George's standing rules (SUPERVISOR §7), which every new phrase follows: times are 24-hour unless am/pm is typed;
monthly repeats keep their original day (a repeat on the 31st lands on the last day of a shorter month and goes back to
the 31st); a repeating task typed after its moment starts at the next occurrence ("every month on the 28th" typed on
the 29th is first due next month); repeat rules store their time of day; a later phrase overrides an earlier one and
the overridden one stays in the title as plain text; a highlight goes away by a tap or by Backspace right after it.

## Items (one commit each, failing test first)
1. **Find out what reads today.** One failing-or-passing core test per phrase below (date typed, expected first due
   date, expected rule, expected highlight range), run against master before you change anything; put the table
   (phrase, before, after) in your report.
   - Day of the month: "every month on the 28th", "on the 28th of every month", "monthly on the 28th", "every 28th",
     "every month on the 1st", "every 1st", "the 28th of each month", "every month on 28".
   - Month intervals: "every other month on the 15th", "every 3 months on the 10th", "every 2 months", "quarterly",
     "every quarter".
   - The month's ends: "every last day of the month", "every month on the last day", "end of every month", "every
     first day of the month".
   - Weekday in the month: "every first Monday", "every first Monday of the month", "every last Friday", "every 2nd
     Tuesday", "every third Wednesday of the month".
   - Yearly: "every year on Mar 3", "every March 3", "yearly on March 3rd", "annually on 3 March", "every year".
   - With a time and with other tokens: "Pay rent every month on the 1st 9am p1 #Finance", "every 28th at 18:30".
2. **Day-of-month and month-interval rules.** Make the first two groups parse, each as one highlight over the whole
   phrase ("every month on the 28th" is one box, as "tom 4" is). Extend `RecurrenceRule` only where its current
   shapes cannot say the rule; a new shape gets a new `encoded` form, round-trips, steps forward correctly across
   short months, leap years and year ends, and never changes how an existing encoded rule decodes (those strings are
   in every user's store and in CloudKit). No model or schema change: `TaskItem.recurrence` is already a string.
3. **The month's ends and weekdays in the month.** The third and fourth groups: "last day" follows each month's own
   length; "first Monday", "last Friday", "2nd Tuesday" step month by month.
4. **Yearly on a date.** The fifth group; "every year" alone keeps today's date.
5. **Show the new rules wherever a repeat is shown.** The words a rule is described with (rows, the editor's Repeat
   row, the Repeat card) must read naturally for the new shapes ("Monthly on the 28th", "First Monday of the month",
   "Yearly on Mar 3"), and the Repeat card must not lose a rule it cannot edit (it shows it as the current choice and
   leaves it alone unless the user picks another). Check the quick-add card, the editor and a row on the iPhone
   simulator and the Mac.
6. **Help text.** Add the new phrases to the quick-add help and the README's quick-add grammar, a line each.

A build that does not know a new `encoded` form reads the task as not repeating. Say in the report which phrases
produce a form older builds cannot decode, so the notes can tell friends to update every device.

## Ownership
`HITListCore/Sources/HITListCore/QuickAddParser.swift`, `QuickAddParser+Disabled.swift`, `DateExpression.swift`,
`RecurrenceRule.swift`, their tests under `HITListCore/Tests/`; in the app only what item 5 and 6 need: the Repeat
card (`HITList/Views/Popouts/Pickers/*` repeat card, the repeat lines of `PopoutPickers.swift`), the repeat line of
`TaskRow`'s meta text if it formats the rule itself, the help text view, `README.md`'s quick-add section, their tests
(`PickerTests`, a new `HITListTests/RepeatPhraseTests.swift`), your `dev/ROADMAP.md` row.
Not yours: `HITList/Views/Flipboard/*` including `FlipInterval` in `FlipboardRules.swift`, `FlipboardSwitch`,
`TaskOrdering`, the models (72: it reads rules but must not need your changes; if a new rule shape makes
`FlipInterval(rule:)` return nil, that is correct and stays); `TokenHighlightField` (no change should be needed: if one
is, stop and report); the Mac chrome (70); `BrowseView`, the bolt (73); `CHANGELOG.md`, `WhatsNew.swift`.

## Done
The phrase table, before and after. Screenshots: the iPhone quick-add card with "Pay rent every month on the 1st 9am"
highlighted and its row after saving; the Mac card with "every first Monday"; the editor's Repeat row for a new rule.
All three suites green (core first: this branch merges first).
