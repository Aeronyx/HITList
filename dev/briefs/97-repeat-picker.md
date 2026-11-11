# Brief 97: choosing a repeat (session `repeat-picker`, effort xhigh)

George, 2026-11-11, after 0.9.3 (three pictures came with it, described in `dev/briefs/ROUND-20.md` and kept
outside git in the shared notes folder, `round-20/george/`):

> For repeated tasks, there should be a custom dropdown like when repeating tasks on a calendar (in the third,
> fourth, and fifth attached screenshots you can see examples of this; Todoist manages this by having a Repeat
> button inside the Pick a Date popout for when a task isn't already set to be repeating).

Picture 3 is our own repeat menu today (seven fixed choices and "Don't repeat"). Picture 4 is Todoist's date
popout with a "Repeat" button at its foot and the menu it opens, each choice worded for the chosen day ("Every
week on Wednesday", "Every month on the 11th", "Every year on November 11th", then "Custom…"). Picture 5 is
macOS Calendar's custom repeat: a frequency, "Every [1] week on:", seven day buttons.

The model can already say all of it: `RecurrenceRule` (core) holds a frequency, an interval, a set of weekdays for
weekly rules, and a place for monthly and yearly ones (a day, the last day, the second Tuesday, a date), and quick
add can type them. Only the pickers cannot: `Views/Popouts/PopoutPickers.swift` offers seven fixed rules.

Read `dev/briefs/COMMON.md` (Round 20 block first), `dev/SUPERVISOR.md` §7 (monthly repeats keep their day; a
repeating task typed after its time starts at the next occurrence; rules store their time of day; custom controls
only), `HITList/Support/DesignSystem/README.md`, `RecurrenceRule.swift`, `PopoutPickers.swift`,
`Views/Popouts/Pickers/*`, and how the editor and the quick-add card show a repeat today.

## Items (one commit each; failing test first where there is logic; pictures of each on both platforms)
1. **The repeat menu, worded for the date.** Wherever a repeat is chosen today (the editor's repeat chip, the
   quick-add card, both platforms), with the task's date as the reference (today when it has none):
   Every day · Every weekday (Mon – Fri) · Every week on Wednesday · Every 2 weeks on Wednesday · Every month on
   the 11th · Every 3 months on the 11th · Every year on November 11 · **Custom…** · and, under a divider when a
   repeat is set, Don't repeat. The words after the first two are quieter, as in picture 4. The rule in force is
   ticked; a rule that is none of the seven (typed in quick add, or made in Custom) shows as its own ticked line at
   the top, in the words the row uses ("Every Tue, Thu and Sat"). The wording comes from one place in core, tested
   for every month length, the 29th to 31st, Feb 29, and each first weekday setting.
2. **Custom…** A small card (iPhone, iPad) or popover (Mac) in our own controls, never a system picker:
   - the frequency: Daily, Weekly, Monthly, Yearly;
   - "Every [n] days / weeks / months / years";
   - Weekly: seven day buttons in the order of Settings → General → Week starts on, at least one on, the date's
     weekday on to begin with;
   - Monthly: on a day of the month, on the last day, or on the first to fifth or last of a weekday, beginning
     with the date's own ("on the 11th", "on the second Wednesday");
   - Yearly: on a month and day;
   - one line at the foot saying the rule in the row's own words; Cancel and Done as in our other cards.
   It can make every rule quick add can type, and opening it on any existing rule shows that rule exactly: test
   the round trip for every kind the parser's tests produce.
3. **A Repeat button in the date picker** (`DatePickerCard`), at its foot, as in picture 4: it opens the same menu
   for the day chosen in the calendar, so a task that does not repeat yet can be given a date and a repeat in one
   visit. When the task repeats, the button shows the rule. Both platforms; the card's height and presets stay.
4. **What choosing does** is what typing it does: the same due date, the same anchor and time handling, the same
   behaviour for a task with no date (it gets the next occurrence). Prove it by comparing each menu choice with
   the parser's result for the same words.
5. **No system date picker is left** (the sweep's finding): Review Inbox's "Pick a date" and Upcoming's swipe "Pick
   Date" open the system's graphical picker (`PickDatePopover`), which also starts its weeks on Sunday whatever
   Settings says. They open our `DatePickerCard` with its presets, like everywhere else.

## Ownership
`HITList/Views/Popouts/PopoutPickers.swift`, `Views/Popouts/Pickers/*`, new files beside them for the menu and the
custom card, the repeat-chip lines of the editor and the quick-add card, the `PickDatePopover` lines of
`Views/Inbox/InboxProcessView.swift`, `Views/Upcoming/TaskRescheduling.swift` and `UpcomingView.swift`, and in
core `RecurrenceRule.swift` for wording and presets only (how a rule steps does not change). Tests of your own and
a UI test file of your own. Not yours: the parser (`QuickAddParser*.swift`, `DateExpression.swift`: brief 98 is in
them now; if a menu choice and the parser disagree, report it to the supervisor rather than editing the parser),
`Views/Flipboard/*` (96), Settings and the toolbar (99), the models' shape, `scripts/`, `dev/`, `CHANGELOG.md`,
`WhatsNew.swift`.

## Done
Pictures: the menu on a task due on the 11th, on the 31st and with no date; Custom for each frequency; the date
picker with its Repeat button; Review Inbox's date picker; on iPhone 17 and the Mac. The round-trip table. All
three suites green, your UI test on a fresh simulator. The branch; changelog lines in plain words; decisions George
might reverse.
