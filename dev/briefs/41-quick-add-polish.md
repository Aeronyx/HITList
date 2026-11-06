# Brief 41: quick-add polish (branch `quick-add-polish`, effort High)

Read `briefs/COMMON.md` first. Six sessions run at the same time; see COMMON's "Round 10 ownership".

George's words, on 0.5.0 (15), 2026-11-04:

> Quickadd highlight taps are good but on desktop my cursor should replace with the "clickable" cursor. Also, if I
> type "tom 3" and then click it to remove it, but then delete it fully and type it again, it should still get
> highlighted.

> A typed reminder like "!15mb" should not highlight before there's a time.

> "X" should still ask Discard, as it already seems to do correctly in this version.

## Items (one commit each, failing test first)

1. **Pointing-hand cursor on the Mac** (`TokenHighlightField.swift`): over a highlight box the cursor is the
   pointing hand (`NSCursor.pointingHand` via the field's tracking areas, or `.pointerStyle(.link)` where it
   applies on macOS 15/26); elsewhere in the text the I-beam as now. iPad with a pointer: the same through
   `.hoverEffect`/pointer style if it is a small change.
2. **A switched-off phrase comes back when retyped** (`QuickAddDraft.swift`, parser `+Disabled`): today the
   disabled set remembers "tom 3" by its text or range, so deleting it and typing it again leaves it plain. A
   disabled phrase is forgotten as soon as its text is no longer in the title (deleted or edited); retyping it
   highlights it again. Keep the sticky-draft behaviour (a restored card shows the same plain/highlighted words).
   Tests: disable, delete, retype → highlighted; disable, edit elsewhere in the title → still plain; disable "tom",
   type "tom" again later in the title → the new one is highlighted, the old stays plain.
3. **Reminders need a time to light up** (`QuickAddParser.swift`; revert part of brief 37): a typed "!15mb" with no
   time stays plain title text and does nothing (George's 0.4.1 rule, which brief 37 reversed). Once a time is
   typed it lights up and counts. The Reminder chip picked before a time: it holds the offset itself (shown on the
   chip, applied when a time arrives) without writing "!15mb" into the title until there is a time; check what
   37's `pendingReminderMinutes` does and keep whichever half still fits. Update 37's tests that pinned the
   reversed rule.
4. **× asks Discard** (check, then fix if needed; `TaskPopout.swift`, the editor's ×; the quick-add card's × is in
   `QuickAddPopout.swift`, owned by session 39, so report rather than edit if that one is wrong): with unsaved
   typing, × asks Discard on the iPhone and the Mac editor; with none it closes. Add a test for the dirty check if
   none exists.

## Ownership
HITListCore `QuickAddParser.swift`, `QuickAddParser+Disabled.swift` and their tests; `Views/Popouts/TokenHighlightField.swift`,
`QuickAddDraft.swift`, `TaskPopout.swift` (× only), `Views/Popouts/Editor/*` (× only); tests `HighlightAreaTests`,
`PopoutTests` (append); ROADMAP row "Quick-add polish (brief 41)". Not yours: `QuickAddPopout.swift` (39),
`PopoutHost.swift` (45).

## Done
All three suites green; iPhone simulator screenshots: "Call !15mb" plain, "Call 3pm !15mb" lit; "tom 3" disabled,
deleted, retyped and lit; × with typing asking Discard. The Mac cursor: say how you verified it (a hosted-window test
of the cursor rects, or the code path) and what George should hover.
