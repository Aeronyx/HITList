# 175: Reminders in quick add: a list on "!", and reminders said in words

Read `dev/briefs/COMMON.md` first (the two sections at its top, the "Round 36" block, the "Round 35 record"), then
this.

George, 2026-11-23, after showing HITList to a friend: "I typed `!0mb` and it didn't register that I wanted a
reminder, nor did spelling out anything about a reminder. This functionality clearly needs a mild improvement.
Todoist handles this better; when the user types an exclamation point on an untimed task, it pops up with
recommendations for "in 5 minutes (!5m), in 15 minutes (!15m)," etc. but when the task does have a time it pops
up with "At time of task (!0mb), 10 minutes before (!10mb)," etc. which is much more user friendly. This is
something we should be able to provide; it shouldn't take me typing out the whole "!0mb" phrase and hitting space
for it to register."

His three screenshots (Todoist on his iPhone) are in the notes folder, `round-36/175/todoist-*.png`. What they show:
- Typing `!` on a task with a time ("9am !") opens a list floating just above the card. Each row has an icon, a
  label, and the code under it in grey: At time of task (!0mb), 10 minutes before (!10mb), 30 minutes before
  (!30mb), 45 minutes before (!45mb), 1 hour before (!1hb), 2 hours before (!2hb), 3 hours before (!3hb), then
  In 5 minutes, and more below.
- On a task without a time ("!"), the list is In 5 minutes (!5m), In 15 minutes (!15m), In 30 minutes (!30m), and
  Later with a clock time under it (4:00 PM).
- After a pick, the title reads "9am !At time of task" with both phrases highlighted, and the date chip says
  "Tomorrow 9:00 AM".

## Why `!0mb` did nothing for him (read in the code and checked with the parser on 2026-11-23)

- **A reminder before the time needs a time typed in the text.** With only a day ("today"), or no date, `!0mb`
  stays as title words (`QuickAddParser.parse`, the "A reminder before the due time is relative to it" block).
  That is right and stays: there is nothing to be "before".
- **A "!" word lights up only after a space** (`Mode.live`, brief 48: George's own request then, so half-typed
  codes don't flicker).
- **Nothing reads a reminder in words.** "remind me 30 minutes before" stays in the title; so does "Remind me to".

The parser on 2026-11-23, Monday 14:10 Eastern, read these dictated lines like this (the Stream ring, brief 176,
will send text like it):

| Text | Today |
|---|---|
| Call mom tomorrow at 5 p.m. | title "Call mom p.m.", due **05:00** |
| Dentist appointment December 3rd at 2:15 p.m. priority 1 | title "Dentist appointment p.m. priority 1", due **02:15**, p4 |
| Task: email Sam about the invoice next Tuesday at 9:30 a.m. | title keeps "a.m." |
| Pick up the dry cleaning at 6. | due tomorrow **06:00** |
| Call mom tomorrow at 5 PM, remind me 30 minutes before. | the reminder words stay in the title |
| Remind me to call mom in 30 minutes. | title "Remind me to call mom", no reminder |

## What to build

### 1. The list on "!" (iPhone, iPad, Mac)

When the word at the cursor starts with one "!" (not "!!", which is priority), a list opens above the card, as in
his screenshots. It belongs to the card: a dark surface of the app's own (`Theme`), rounded, the card's shadow; no
system menu.

- **The task has a time** (typed in the text, or set by the Date chip, which writes it into the text): At time of
  task, 10 minutes before, 30 minutes before, 45 minutes before, 1 hour before, 2 hours before, 3 hours before,
  1 day before, then In 5 minutes, In 15 minutes, In 30 minutes, Later.
- **No time**: In 5 minutes, In 15 minutes, In 30 minutes, In 1 hour, Later.
- **Later** shows a clock time under it: three hours from now, rounded up to the next whole hour; if that is after
  10 PM, Tomorrow 9:00 AM instead.
- Each row: an icon (SF Symbols that read as Todoist's do: a clock for "before", a calendar-with-clock for "in",
  a forward clock for Later), the label, and the code under it in `Theme.secondaryText` (the code is what a
  person can type instead next time).
- **Typing narrows it**: "!1" keeps the rows whose code or label number starts with 1 (10 minutes before, 1 hour
  before, 1 day before, In 15 minutes, In 1 hour); "!h" the rows with a word starting with h; "!in" the In rows;
  "!at" At time of task. Nothing matches: the list closes. A space closes it.
- **A pick** replaces the typed "!…" with the row's phrase and a space, lit at once (no space to type), and the
  chips show it. The keyboard stays up and the cursor sits after the space.
- **Mac**: the list opens under or over the field, wherever it fits in the window. ↑ and ↓ move a highlight
  (first row highlighted on open), Return picks it and does **not** add the task, Esc closes the list (a second
  Esc does what Esc does today). The mouse picks too.
- **iPhone**: the list sits above the card and never under the keyboard or off the top of the screen. It holds
  six to seven rows and scrolls for more, as his screenshots do.
- VoiceOver: each row is a button read as its label then its code ("10 minutes before, exclamation 10 m b").
- The task editor's title (`TaskPopout`, `TaskEditorDraft`, where `dueTimeIsSet` lets "before" count with no time
  typed) gets the same list if it is the same field and it costs little; otherwise leave it and say so.

### 2. What a pick writes: words, as Todoist does

The list and the Reminder chip write the same readable phrase, and the codes keep working when typed:

| Row | Writes | Code that still works |
|---|---|---|
| At time of task | `!At time of task` | `!0mb`, `!at`, `!0` |
| 10 minutes before | `!10 minutes before` | `!10mb` |
| 1 hour before | `!1 hour before` | `!1hb` |
| 1 day before | `!1 day before` | `!1db` |
| In 5 minutes | `!In 5 minutes` | `!5m` |
| In 1 hour | `!In 1 hour` | `!1h` |
| Later (4:00 PM) | `!4:00 PM` | `!4pm` |

That means the parser reads multi-word "!" phrases. Rules:

- `!At time of task`, `!at time`, `!at the time`: zero before the due time.
- `!N minute(s)|min(s)|hour(s)|hr(s)|day(s) before`, with N a number, a number word up to twelve, "a" or "an":
  that long before the due time (needs a time, as the codes do).
- `!In N minutes|hours|days`, `!in an hour`, `!in half an hour`: that long from now (`reminderFromNow`).
- `!` followed by a clock time (`!4pm`, `!4:00 PM`, `!4 p.m.`, `!16:00`; `!at 4pm` too): a reminder at that moment,
  stored as `reminderDate`. On the task's due day when it has a due date, otherwise today if that time is still
  ahead, otherwise tomorrow. Check that a parsed `reminderDate` with no `reminderFromNow` reaches the saved task
  (`QuickAddDraft.result`, `TaskActions.create`) and the notification; it may only have come from the Reminder
  card's "Later today…" until now.
- Case and trailing ",.;" don't matter. A phrase is one token (one highlight, one switch-off), and the live rule
  stays: while its **last** word is still being typed at the very end, it is plain text. "!10 minutes" (no "before",
  no "in") is not a phrase.
- Everything that reads a reminder token's text today (`ReminderPhrase(token:)`, `QuickAddDraft.reminderTokens`,
  the switched-off phrases in `QuickAddParser+Disabled`, the editor's `TitlePhrases`, `ReminderChipText`) reads both
  forms. The chips' writers (`QuickAddDraft.setReminderOffset`, `setReminderMoment`, `ChipToken`) write the words.

### 3. Reminders said in words (typed, Siri, the ring)

- `remind me` or `reminder`, followed by any phrase of §2 without the "!" ("remind me 30 minutes before",
  "reminder in an hour", "remind me at 4pm", "remind me at the time"): the same reminder, one token (kind
  `.reminder`), the words out of the title. Not followed by such a phrase: title words, as now ("Remind Sam about
  the party", "Reminder: pay rent", "remind me").
- **"Remind me to …" at the start** of the text: the three words are a token too (switching it off puts them back),
  the title is the rest with its first letter capitalized, and when the text gives the task a time ("tomorrow at
  5", "in 30 minutes") and no other reminder, the reminder is at the time of the task. "Remind me in 30 minutes to
  call mom": the reminder phrase, then a leading "to" leaves the title ("Call mom").
- **"priority 1" to "priority 4"** (and "priority one" to "four"): p1 to p4, as "p1" is.

### 4. Times as people say them

- **"5 p.m.", "5 P.M.", "9:30 a.m.", "2:15 p.m.", "5 pm", "5pm."**: the right half of the day, every dot and space
  consumed (no "p.m." left in the title). "noon" and "midnight" if they are not read yet. Siri's path already
  rewrites "p.m." before parsing (`IntentActions.dictationNormalized`, in brief 176's file): read it in the parser
  itself so the card, Siri, Claude and the ring all get it, and leave that function where it is (the supervisor
  removes it after both merge).
- **"at 1" to "at 6" with no am/pm**: the afternoon (1 PM to 6 PM). Nobody means "pick up the dry cleaning at 6" at
  six in the morning. "at 7" to "at 11", and a bare hour after a date word ("tomorrow 5", "friday 9", read on a
  24-hour clock since brief 37), stay as they are. List every test whose expectation this changes, and why.

### 5. The words that explain it

- The quick-add guide's reminder lines (`HITList/Views/Help/QuickAddGuide.swift`, `QuickAddGuideView.swift`) and
  the tip that names reminders, if any: the list, the words, and one line of codes for those who like them.
- `ClaudeTools.addTask`'s description: reminders in words ("remind me 30 minutes before", "!in 15 minutes") as
  well as the codes.
- Not `WhatsNew`, `CHANGELOG.md` or the version: the supervisor writes those.

## Bounds

- **Yours**: `HITListCore/Sources/HITListCore/QuickAddParser*.swift`, `DateExpression.swift`, a new
  `ReminderSuggestions.swift` (the list's rows, narrowing and Later's time, pure and tested),
  `AutocompleteEngine.swift` if you need it, `ClaudeTools.swift`'s text; in the app `HITList/Views/Popouts/**`
  (the card, the draft, `TokenHighlightField`, `Pickers/ReminderPickerCard`, the chips, the editor's title
  phrases), `HITList/Views/Help/QuickAddGuide*.swift`; their tests (`HITListCore/Tests/**` for what you touch,
  `HITListTests/QuickAdd*`, `TaskPopout*`, `HITListUITests/` classes of your own).
- **Not yours**: `HITList/Services/**` (brief 176 is in `Services/Intents` and a new `Services/Inbox`; the
  supervisor in the sync files), `HITList/Views/Settings/**` other than the guide, `HITListApp.swift`, the
  version, `WhatsNew`, `CHANGELOG.md`, `project.yml` beyond what XcodeGen picks up by itself.
- A simulator of your own named `HITList-175` (iPhone 17) and a derived-data folder of your own
  (`build.noindex/175`); the Mac through `scripts/window-shot.sh` / `window-drive.sh` on your own Debug build with
  a side store (`HITLIST_STORE_SUFFIX=r36-175`, `-disableCloudKit YES`). Delete both when you finish. Nobody's
  phone.

## Proof (yours to make and to look at)

- Core tests: every row of every list parses back to what the row says (both forms), the narrowing, Later's time
  around 7 PM and 10 PM, the phrases of §2 and §3 and their negatives, the times of §4 (each line of the table
  above, with what it now reads), live mode for a multi-word phrase.
- Hosted tests for the draft: a pick replaces the typed "!…" and lights; the chips write the words; switching a
  phrase off; a time removed holds a "before" reminder as today (`holdReminderForLater`).
- UI tests on the simulator: "Call mom 9am !" shows At time of task first, a tap gives "!At time of task " lit and
  the Reminder chip says "At time", Add saves a task whose reminder is at 9:00; "Buy milk !1" narrows, In 15
  minutes picks, Add saves a reminder fifteen minutes on; on the Mac the same with ↓ and Return (Return does not
  add).
- Pictures in the notes folder (`round-36/175/`): the list timed, untimed and narrowed on the iPhone (iPhone 17
  and the smallest supported size), after a pick, the Mac's list; **look at every one yourself** against his
  screenshots: nothing under the keyboard, nothing cut off, text clear of every edge (12 pt floors, COMMON).
- `SIMULATOR=HITList-175 scripts/test.sh ios`, `scripts/test.sh core macos` green on your tree, and your UI classes
  to their last test, before you report. Run each new test once against the code before your change, to see it
  fail.
- Commit each item the moment it is whole. No push, no merge, no `scripts/release.sh`.

## Report

What a person sees and gets for each of his three screenshots' cases; the phrases the parser reads now, and what
it did not take (and why); each test whose expectation changed, and why; pictures' folder and count; tests and
their counts before and after; your branch and commits; your simulator and folder deleted.
