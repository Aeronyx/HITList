# Brief 39: the board's inline add card (branch `board-inline-add`, effort High)

Read `briefs/COMMON.md` first. Six sessions (40–45) run at the same time; see COMMON's "Round 10 ownership".

George's words, on 0.5.0 (15), 2026-11-04 (with a screenshot of the Mac board: a day column whose foot is a compact
card, "Task name" placeholder with the cursor in it, chips "+", "Today ×", "Priority", "Reminders", "Inbox" wrapping
onto two lines inside the column width, "×" and the send pill bottom-right):

> Upcoming tab looks solid so far on desktop. One issue is that, like mobile, clicking "Add task" should
> automatically select the text box so I can start typing immediately. Another issue is that, instead of having
> the full "Add task" popout on desktop, adding a task in-line should make a smaller "Add task" popout centered
> only on that day (screenshot attached; example is in the bottom right).

## Items (one commit each, failing test first where there is logic)

1. **Inline card in the column** (`Views/Upcoming/UpcomingBoard.swift`, new `Views/Popouts/CompactQuickAddCard.swift`):
   "+ Add task" at a column's foot turns into a compact quick-add card inside that column, as wide as the column
   (≈ 270 pt minus its padding), replacing the Add row while open; the column scrolls so the card is visible. It is
   the same quick add (same `QuickAddDraft`, parser, `TokenHighlightField` highlights, chips, sticky-draft rules,
   Discard on click-away with content) in a compact layout: title field, chips wrapping (`+`, the day chip with ×,
   Priority, Reminders, Group), "×" and the Confirm pill. Reuse `QuickAddPopout`'s pieces: give it a compact style
   or extract the shared body, rather than writing a second quick add. Confirm adds the task on that day (the day
   context already exists) and keeps the card open and empty for the next task, as Todoist does; Esc or × closes it.
   One inline card at a time across the board.
2. **Focus at once** (both the inline card and every other Mac quick add): the title field has keyboard focus the
   moment the card appears, with no click. Check the toolbar "+", ⌘N, and the board; on iPhone it already works,
   keep it so. Test the focus request where it can be tested; otherwise say how you verified it.
3. **iPad regular width** gets the same inline card on its board.

## Ownership
`Views/Upcoming/UpcomingBoard.swift` (+ its card file), new `Views/Popouts/CompactQuickAddCard.swift`,
`Views/Popouts/QuickAddPopout.swift` (compact style / shared body, Mac focus), `QuickAddEntry.swift` (Mac focus only);
tests `UpcomingBoardTests` and a new `CompactQuickAddTests`; `project.yml` only to add files; ROADMAP row "Board
inline add card (brief 39)". Not yours: `TokenHighlightField.swift`, `QuickAddDraft.swift`, the parser (41),
`PopoutHost.swift` (45), `TaskPopout.swift` (41).

## Done
All three suites green; offscreen PNGs of a board column with the inline card open (empty, and with "Call Sam p1
3pm" highlighted) since the Mac cannot be screenshotted; iPad landscape simulator screenshots of the same; the
report lists what George should try on the Mac.
