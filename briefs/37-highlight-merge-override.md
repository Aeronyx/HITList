# Brief 37: joined highlights, earlier phrases come back (branch `highlight-merge-override`, effort High)

Read `briefs/COMMON.md` first. Sessions 34 (account, data model) and 38 (Mac Upcoming board) run at the same
time; 36 (task editor, Confirm, the field's Return key) starts after you are merged and edits the
`submitLabel`/`onSubmit` lines of `TokenHighlightField.swift`, so keep your edits there to the highlight areas,
drawing and tap targets.

George's words, from the 0.4.1 (14) feedback on 2026-11-04:

> Quickadd highlights should fill the space between words if they're next to each other and have the
> same color highlight/category; for example, in the third attached screenshot, "[tom] [4]" should be
> "[tom 4]" visually. Also, if a later quickadd highlight is to overwrite an earlier one, let it, but
> clicking/tapping on it to remove it should then restore the first quickadd highlight (e.g. "jan 6
> zach fox [in a month]" reverts to "[jan 6] zach fox in a month").

The screenshot: the quick-add card with "test 2 [p1] [tom] [4]", three separate rounded boxes, chips
Tomorrow · P1 · 4:00 AM ("tom 4" = 04:00 is George's rule, kept on purpose).

## Items (one commit each, failing test first)

1. **Superseded phrases** (HITListCore `QuickAddParser.swift`, `QuickAddParser+Disabled.swift`): when a later
   phrase of the same kind wins (a second date phrase, a second priority, a second reminder, a second repeat…
   check which kinds can be overridden today), the earlier one becomes a token marked `superseded` (no
   highlight, no effect on the result) instead of vanishing from the token list. Disabling the winner
   (`disable`, the tap) re-parses so the most recent remaining phrase of that kind applies again and is
   highlighted. Tests: "jan 6 zach fox in a month" → due = in a month, "jan 6" superseded; disable "in a month"
   → due Jan 6, "in a month" plain text; three phrases, disable the last → the middle one wins; disable the
   middle while the last wins → nothing visible changes; p1 … p3 the same way; a date and a time in separate
   phrases ("tom 4") are complementary, not superseding (both stay).
2. **Joined boxes** (`TokenHighlightField.swift`'s `areas` and drawing, plus the hit-testing for taps): two or
   more highlighted tokens of the same kind (same colour) separated only by whitespace on the same line draw as
   one rounded box covering the gap ("[tom 4]"); a wrap to the next line splits the box at the line end as
   today. Decide what a tap on a joined box does and test it: George's words say the boxes look joined, not that
   the phrases merge, so the natural rule is that a tap disables every token in the joined box (one tap,
   "tom 4" becomes plain text) — implement that and say so as a decision George might reverse. Put the tests in
   a new `HITListTests/HighlightAreaTests.swift` (session 36 appends to `PopoutTests`).
3. **The reminder chip before a time** (open item from 0.4.1; `QuickAddDraft.swift` / the parser): picking a
   reminder offset from the chip before the task has a time leaves "!15mb" in the title as plain text until a
   time is picked. It should be highlighted as soon as it is there and take effect when a time arrives (or the
   chip should hold it without writing text; read how the chip writes it and pick the smaller change). Test it.
4. **Draft plumbing** (`QuickAddDraft.swift` `disable`): the sticky-draft store keeps the disabled set and the
   superseded state across an app kill exactly as today (a restored card shows the same boxes).

## Ownership

HITListCore `QuickAddParser.swift`, `QuickAddParser+Disabled.swift` (and `DateExpression.swift` only if a
superseded phrase needs its range) and their tests; `HITList/Views/Popouts/TokenHighlightField.swift` (areas,
drawing, tap targets; not the submit lines), `QuickAddDraft.swift` (`disable`, reminder text, sticky store);
new `HITListTests/HighlightAreaTests.swift`; `project.yml` only to add files, then `xcodegen generate`; ROADMAP
row "Joined highlights, earlier phrases come back (brief 37)".

Not yours: `QuickAddPopout.swift` (36 owns its footer and title submit; if you need a change there, report it),
`PopoutHost.swift`, `TaskPopout.swift`, `Views/Upcoming/*`, model and Settings files.

## Done

All three suites green (core count up by your tests); iPhone simulator screenshots of the quick-add card:
"test 2 p1 tom 4" with "[p1]" and one "[tom 4]" box (p1 is red, the date green: different kinds stay apart);
"jan 6 zach fox in a month" with only "in a month" highlighted, then after tapping it "jan 6" highlighted and
the chip back on Jan 6; the reminder picked before a time.
