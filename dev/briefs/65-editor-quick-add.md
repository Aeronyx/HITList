# Brief 65: the editor's title understands quick add; every Mac card works (session `editor-quick-add`, effort xhigh)

George, 2026-11-08, on 0.8.1 (screenshot `/Users/gtrammell/Desktop/HITList/build.noindex/round-15/george-3-mac-editor.png`:
the Mac editor with "test today" typed in the title and the date still "No date"):

> Trying to click "No date" to add a date while editing a task on Mac does nothing. It also doesn't respect quickadd
> (third screenshot). Why are tasks broken? I think the calendar/groups dropdowns are invisible. What a mess.

Read `dev/briefs/COMMON.md`, `dev/briefs/ROUND-15.md`, then `32-subtasks-editor.md`, `36-editor-space-confirm.md` (the
editor and Confirm), `47-highlight-engine.md` and `41-quick-add-polish.md` (highlights on native text views, Backspace,
keeping a phrase as text). The invisible cards are fixed on master (`804843a`: the card layer now sits in the window's
frame view); the rest is yours.

## Items (one commit each, failing test first where there is logic)
1. **The title reads quick-add phrases.** Typing in the editor's title highlights phrases exactly as the quick-add
   card does: the same `QuickAddParser` (the person's Groups and labels known), the same highlight look on the same
   native text views (`TokenHighlightField` / `HighlightText`), a click or tap keeps a phrase as plain text, Backspace
   right after a highlight removes the highlight first. What is highlighted shows below as it will be saved (the date
   row reads "Today" while "today" is highlighted, the priority pill fills for "p1", the Group row for `#Work`, labels,
   reminder, repeat) and Confirm saves it: the phrase leaves the title, the fields take the values. × and Esc discard
   as now (Discard is asked when there is typing). Only what is typed in this editing session is read: a title that
   already holds a word like "today" keeps it as plain text until it is typed again. iPhone and Mac. Tests for the
   parse-and-apply rules (the title, each field, a kept-as-text phrase, an existing title left alone).
2. **Every card on the Mac, checked by hand.** After `804843a`, open every card in the editor (date row, Group row,
   Priority, Reminder, Labels, Repeat, Deadline, Location), in the quick-add card (each chip) and on the Upcoming
   board's add card: it shows under its chip, a click picks, Tab moves into it, Esc and a click outside close it, the
   value lands. Screenshot each with `scripts/window-drive.sh`. Fix anything still wrong in `Pickers/*` or the editor.
3. **The date row is the editor's way to a date.** Clicking "No date" (or the date) opens the date card at once with
   the keyboard in its time field reachable by Tab; picking a day closes it and the row shows the day. A UI test on
   iPhone (`HITListUITests`) taps the date row, picks Tomorrow and sees it.

## Ownership
`HITList/Views/Popouts/TaskPopout.swift` (everything but `groupRow`, which brief 64 changes), `HITList/Views/Popouts/Editor/*`,
`HITList/Views/Popouts/Pickers/*`, `HITList/Views/Popouts/TokenHighlightField.swift`, `HITList/Views/Popouts/HighlightText/*`,
`HITListTests/TaskPopout*Tests.swift`, `HITListTests/PickerTests.swift`, new editor tests, your UI test in
`HITListUITests/HITListUITests.swift`, your `dev/ROADMAP.md` row.
Not yours: `QuickAddPopout`, `CompactQuickAddCard`, `PopoutPickers`, `PopoutHost`, `PopoutController` (64; the quick-add
card must keep working exactly as it does, so a change you need in `TokenHighlightField` must leave the card's
behaviour and its tests unchanged), `HITTokens` (67), core `QuickAddParser` (use it as it is; if it truly needs a
change, make the smallest one with a core test and say so in the report).

## Done
On the Mac and the iPhone 17 simulator: "Call mom tomorrow 5pm p1" typed into an existing task's title, highlighted,
the rows below showing tomorrow 17:00 and P1, Confirm saving it with "Call mom" as the title. The Mac screenshots of
item 2, one per card. All three suites and the UI tests green.
