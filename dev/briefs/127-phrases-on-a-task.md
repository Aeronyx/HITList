# Brief 127: a typed phrase that leans on the task: "!30mb" in the editor, and every case like it (0.9.9)

Read `dev/briefs/COMMON.md` (the Round 25 block first), then this. **Report due 100 minutes after you start.**
Effort: xhigh.

## George's words (2026-11-12, on 0.9.8), with a friend's screenshot
"First, one of my friends noticed an issue where, when editing a task, typing !0mb wouldn't register a reminder
even though that task already had a time (screenshot attached). I'm guessing this is because we made it so that
quickadd reminders only work when a quickadd time is present, but they must also work when editing a task that
already has a time associated with it. This same edge case could cause issues with other interactions as well;
please scan for and fix any problems."

The screenshot: the task editor's title card. Title "PNHP Working Group tonight !30mb", the caret right after
"!30mb", nothing in the title highlighted; under it "Inbox" and "Today 8:00 PM". (He wrote "!0mb"; the picture
says "!30mb". `!0mb` is not in the grammar and `!0` is: see item 3.)

## What is there (read it before you believe anyone's guess, George's and mine included)
- `HITListCore/Sources/HITListCore/QuickAddParser.swift`: a reminder before the due time (`!15mb`, `!at`, `!0`)
  counts only beside a typed time, **or** when `dueTimeIsSet` is true (lines 203 to 215; brief 65 added the flag
  for the editor). `ReminderPhrase`, `ReminderOffset` below it. `Mode.live` leaves a "!" word at the very end of
  the text, with no space after it yet, as plain text (brief 48, George: a "!" phrase "only checks/adds a highlight
  after the user presses space instead of while they're typing it").
- `HITList/Views/Popouts/Editor/TaskEditorDraft.swift`: `parsed(_:for:_:)` sets `dueTimeIsSet = task.hasDueTime &&
  task.dueDate != nil`; the stored title's words stay plain until typed again (`untouched`); Confirm (`commit`)
  reads `.final`. `TitlePhrases.swift` turns the parse into fields and applies them. `TaskPopout.swift` builds the
  parser (`parser(now:)`), shows the live phrases, commits at line 675, and swaps picks for typed phrases (line 690
  on).
- So on paper the plain case works, and `ReminderGrammarTests` has a case for the flag. The friend saw it fail.
  Find out how, in the running app, before you change a line.
- Every other place that builds a parser: `QuickAddPopout.swift:87` (the card; chips and the draft hold values the
  text does not), `InboxProcessView.swift:71`, `Flipboard/SwitchCard.swift:111`, `Services/TaskActions.swift:422`,
  `Services/Claude/ClaudeToolHandler.swift:134` and `:244`, `Services/Intents/AddTaskIntent.swift:100`,
  `Services/Share/ShareInbox.swift:169`, `HITListShare/ShareSheetModel.swift:59`, `Help/QuickAddGuide.swift:59`.

## What to do, in this order (a failing test first for every defect; one commit each)
1. **Reproduce the friend's case** on an iPhone simulator and in a Debug Mac app of your own: a task due today at
   8 PM; open it; type " !30mb" at the end of the title. Try each of: Confirm with no space after it; Return in the
   title; a space, then Confirm; the phrase typed in the middle; the title already holding "!30mb" as stored text
   when the editor opens (typed in quick add when there was no time, then a time picked later); the time picked in
   the editor's date card in this same editing session, before the phrase and after it; a time typed in the title
   in this same edit ("9pm !30mb") on a task that has none; a repeating task; a task whose time was set by a
   Switchboard; a Shared Task; every way the editor closes or saves other than Confirm (swipe down, ×, Esc, a click
   away, the app going to the background). Write down for each what the title shows while typing, what the
   reminder row shows before Confirm, and what is stored after. The ones that are wrong are the bug: say which.
2. **Fix it** so that, in George's words, a reminder phrase works "when editing a task that already has a time
   associated with it": typed anywhere in the title, on either platform, however the edit is confirmed. The
   reminder row in the editor must show what Confirm will save, before Confirm. Brief 48's rule about a "!" word
   still being typed stays as it is in the quick-add card; if it is the cause in the editor (nothing lights up, so
   it looks dead), say so and make the editor's own behaviour honest (for example the reminder row previews it, or
   the last word counts in the editor), and name the choice in your report as one George may reverse.
3. **The grammar's near misses.** `!0mb`, `!0hb`, `!0b`: decide with the grammar's own logic whether "zero before"
   is "at the due time" like `!0` and `!at` (it reads that way) and, if so, accept it with tests in
   `ReminderGrammarTests`; anything else unchanged.
4. **The scan he asks for.** The fault's shape is: *a phrase whose meaning leans on something the text beside it may
   not hold, because the task, the draft or a chip holds it instead.* Go through every parser call site above and
   every such phrase, and fill a table for your report (site × phrase: what it leans on, where that comes from
   there, right or wrong, the test that now pins it):
   - a reminder before the due time leans on a time: the task's (editor), a chip's or the date card's (quick-add
     card, Inbox review, the Switch card, the share sheet), an argument's (Siri, Claude's `add_task` and
     `update_task`);
   - a bare time leans on a day; a day typed on a timed task keeps the time; "in 2 hours" sets both;
   - a repeat leans on the day and time it starts from, typed or the task's; "starting <day>" leans on a repeat,
     typed or the task's;
   - a reminder from now (`!15m`) on a task whose due time is earlier than that moment; a reminder kept when the
     time it leans on is then removed in the same edit (what is stored must not be a reminder with nothing to count
     from);
   - a phrase switched off by a tap, and one in the stored title, stay text everywhere;
   - anything else you find of the same shape. Fix what is wrong, each with its test. Where two readings are both
     defensible, keep today's and list it.
5. **A UI test** for the friend's case on the iPhone (open a timed task from seeded data, type the phrase, Confirm,
   read the reminder on the row or in the editor) and the same check on the Mac by `scripts/window-drive.sh` or a
   hosted test, whichever is honest.

## Ownership
`HITListCore/Sources/HITListCore/QuickAddParser*.swift` (and `DateExpression.swift` only if a fix needs it), the
core tests; `Views/Popouts/Editor/TaskEditorDraft.swift`, `TitlePhrases.swift`, the title and phrase parts of
`TaskPopout.swift`; `QuickAddDraft.swift`, `QuickAddPopout.swift`, `QuickAddContext.swift` where the scan finds a
fault; the parser call and what feeds it in `InboxProcessView.swift`, `Flipboard/SwitchCard.swift`,
`TaskActions.swift`, `ClaudeToolHandler.swift`, `AddTaskIntent.swift`, `ShareInbox.swift`,
`HITListShare/ShareSheetModel.swift`; their tests and one UI test class of your own. No model change (if a fix
seems to need one, stop and tell the supervisor). Nothing under `Support/Companions`, `Views/Companions` or
`Views/Settings`: four sibling sessions are there.

## Done
- The friend's case works on iPhone and Mac, seen running; the table of item 1 (before) and item 4 (after) in the
  report; every defect has a test that failed first.
- `scripts/test.sh core`, `macos` and `ios` green (your own simulator, `HITList-127`), and your UI class.
- The report COMMON asks for: per commit, counts before and after, how it was seen running, changelog lines in
  plain words a friend would understand, and every choice George may reverse.
