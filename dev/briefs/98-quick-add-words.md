# Brief 98: more words for quick add, and a guide to it (session `quick-add-words`, effort high)

George, 2026-11-11, after 0.9.3:

> Have quickadd ignore the word "starting", and add detection/support for multi-day phrases such as "vacuum on
> tuesday thursday and saturday".
>
> Make a "?" help page in a good spot inside Settings/Browse to explain/show very concisely to users how to use the
> quickadd system to the fullest.

Read `dev/briefs/COMMON.md` (Round 20 block first), `dev/SUPERVISOR.md` §5 (where quick add lives) and §7 (the
decisions about it: 24-hour times unless am/pm is typed, "tom" stays, a highlight goes away by a tap or by
Backspace right after it, overridden phrases stay in the title as plain text, "!" reminders, `!15m` and `!15mb`),
then the parser and its tests in `HITListCore`. Almost all of this brief is core: `cd HITListCore && swift test`
runs in a minute; build the app only for the guide.

## Items (one commit each, failing test first)
1. **"starting" is not a title word** when it joins a repeat to its first day: "water plants every 3 days starting
   friday", "every 2 weeks starting nov 24", "starting monday every weekday", "starting tomorrow". The word is part
   of the highlight, the day after it is the first occurrence, the title is "water plants". Also "starting on" and
   "starting from". It stays a title word wherever no date follows it ("email the starting lineup", "starting
   salary talk fri"): write those false positives as tests first, and more of your own.
2. **Several weekdays at once repeat weekly.** "vacuum on tuesday thursday and saturday", "vacuum tue thu sat",
   "every mon, wed & fri", "gym mon/wed/fri 7am", "on weekdays", "weekends" where they parse today: one task that
   repeats every week on those days (`RecurrenceRule(frequency: .weekly, weekdays:)`), due on the next of them,
   with or without "every" (the supervisor's reading: a task has one date, so three days named together can only
   be a repeat; one weekday alone stays a date, as today). The highlight covers the whole phrase and the chip
   shows the repeat, so the person sees what was understood before saving; tapping the highlight turns it back
   into title words, as for any other. Two days that are not a list stay what they are today ("call mom fri about
   sunday" is Friday, and "sunday" a title word): write those tests first. An interval and a start still work
   ("every 2 weeks on tue and thu starting dec 1").
3. **The guide.** A short page that shows, not tells, what quick add understands:
   - each line is something a person would type, drawn with the real highlights by the real parser (so the page
     can never drift from the parser: a test parses every example and checks what its caption claims), with a
     caption of a few words; grouped under a few headers: when (tom, fri, nov 24, in 3 days, next mon, a time),
     repeats (every day, every 2 weeks, several weekdays, every month on the 28th, the last Friday, starting…),
     reminders, priority, labels, Groups, and whatever else the parser knows that a person would not guess (read
     its tests for the list; leave out what is obvious);
   - "very concisely": it should fit two iPhone screens at most, no paragraphs;
   - tapping an example opens quick add with it typed, if that falls out of the card's own entry point without new
     machinery; leave it out otherwise and say so.
   **Where:** one tap from Browse on iPhone and iPad (a "?" beside the gear, or the best spot you find: show the
   candidates), a row in Settings → General ("Quick add guide"), and on the Mac the Help menu's first item and the
   same Settings row. Not on Settings' first screen (it has no room: it must still fit an iPhone 16 without
   scrolling). It opens as a page of the sheet or a card in our own style, never a system help window.
   Dates in the examples are computed from today, so a picture taken tomorrow is still right.

## Ownership
Core: `QuickAddParser*.swift`, `DateExpression.swift`, the autocomplete if a new phrase needs it, and their tests.
App: new files under `HITList/Views/Help/`, the one "?" in `Views/Tabs/BrowseView.swift`, one row in Settings →
General (iPhone's page and the Mac's section), one Help-menu item where the app's commands live, tests and a UI
test file of your own. Not yours: `RecurrenceRule.swift` (97 is wording it now; you only construct rules: if
stepping a several-weekday rule is wrong, say so with a failing test and the supervisor will sort out who fixes
it), the pickers (97), every other Settings line (99), `scripts/`, `dev/`, `CHANGELOG.md`, `WhatsNew.swift`.

## Done
The phrases that now parse and the false positives that still do not, as a table. Pictures of the guide on iPhone
17 and the Mac and of each way in. Core's test count before and after; all three suites green once, at the end.
The branch; changelog lines in plain words; decisions George might reverse.
