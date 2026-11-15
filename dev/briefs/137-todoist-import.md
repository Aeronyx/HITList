# Brief 137: import from Todoist (session `todoist-import`, effort xhigh)

George, 2026-11-14 (he is moving his own tasks over, and his friends came from Todoist too):

> Is there an easy way to allow importing my tasks from Todoist?

Yes. Todoist gives a person their data two ways without any sign-in from us: **its backups** (Settings → Backups
in Todoist: a ZIP with one CSV per project) and **a project's CSV** (the project's ⋯ menu → Export as CSV). This
brief reads both. (Todoist's API with a personal token would be a third way; not this round.)

Read `dev/briefs/COMMON.md` (the Round 27 block first), `dev/briefs/ROUND-27.md`, the design system README, then
`Models/Models.swift` (what a task, a Group, a label and a sub-task can hold; `deadline` exists), `TaskActions.swift`
(how tasks are made), core `QuickAddParser`, `DateExpression`, `RecurrenceRule` (what dates and repeats HITList
can already read), `Views/Settings/DataSettingsGroups.swift` (`ExportImportGroup`: "Import JSON…" is the
neighbour), `Services/LocalBackup.swift`.

**Look the format up before you write the parser** (Todoist's help pages on importing and exporting CSV
templates and on backups; give the URLs in your report). As the supervisor remembers it, to be checked: a header
row `TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT,AUTHOR,RESPONSIBLE,DATE,DATE_LANG,TIMEZONE,DURATION,DURATION_UNIT`
(newer exports add `DEADLINE`, `DEADLINE_LANG` and others); rows of `TYPE` `task`, `section` and `note` (a note
belongs to the task above it), blank rows between; `PRIORITY` 1 to 4 with 1 the highest; `INDENT` 1 to 5 for
sub-tasks; `DATE` in words in the language `DATE_LANG` names ("every day", "14 Nov", "every mon, wed at 9am",
"2026-11-20 14:00"), often without a year; labels typed in `CONTENT` as `@name`; a backup's files named like
`Work [2301234567].csv`. Read columns by name, in any order, and survive ones you do not know.

## The rules
- **Additive only.** The import creates Groups, labels and tasks. It never edits or deletes anything that was
  there. No schema change. A backup (`LocalBackup`) is taken before the first record is written.
- **Nothing is written before the person has seen what will be.** A preview, then one button.
- **A second run doubles nothing.** A task that matches one already in HITList (same title, same Group, not
  completed) is skipped and counted.
- **Nothing is lost silently.** Whatever HITList cannot hold goes into the task's notes in plain words, and the
  preview counts it.
- **It can be undone.** The import keeps the ids of what it made (a small file on the device, not synced); "Undo
  last import" on the same Settings page removes exactly those, after a question that names the counts, until the
  next import replaces the receipt. (Deleting is right here because the person asks for exactly these records to
  go; it is not a reset.)

## Items, in this order (one commit each, failing test first)
1. **The reader, pure, in `HITListCore`**: CSV by the standard (quotes, doubled quotes, commas and line breaks
   inside a field, a byte-order mark, CRLF), then Todoist's rows into a small tree: project → sections → tasks →
   sub-tasks and notes. Fixtures written to the documented format, and the awkward ones (a title with a comma and
   a quote, a description of several lines, an unknown column, a file with no tasks).
2. **The mapping, pure, in core**, with a report of every choice it made:
   - a project is a Group of that name (an existing Group of the same name is used; Todoist's Inbox goes to
     HITList's Inbox, ungrouped);
   - a section becomes a label named after it (one switch on the preview: "Keep sections as labels", on);
   - `@name` in a title becomes that label (made if missing) and leaves the title;
   - priority 1 to 4 becomes HITList's;
   - `DATE`: read with HITList's own date and repeat readers first; add what Todoist writes and they lack (look
     at real exports: day and month without a year means the next such day, never one already months past;
     "every day/week/month/year", "every weekday", "every 2 weeks", lists of weekdays, "every 15th", "every last
     day", "ev", "every!" and "after" forms, "starting"/"until", a time in 12- or 24-hour form; `TIMEZONE` for a
     timed date; `DATE_LANG` other than English kept as text). A date it cannot read: the task comes in with no
     date and "Todoist date: <text>" as the first line of its notes, and the preview lists every such task;
   - `DEADLINE` becomes the task's deadline; `DESCRIPTION` its notes; `note` rows are added under the notes,
     each on its own line; `DURATION` goes to the notes;
   - sub-tasks: HITList's are one level, a checklist with no date of their own. A sub-task with no date,
     priority or label of its own becomes a checklist line of its top parent (deeper levels flattened, "A › B");
     one that has any of them becomes a task of its own with "Under: <parent>" in its notes. Counted both ways;
   - a title starting `* ` (Todoist's uncompletable heading) comes in as a label-less task with the star removed
     and "Heading in Todoist" in its notes.
3. **The ZIP.** A backup is one file: read it without asking the person to unzip (a small reader for stored and
   deflated entries over the `Compression` framework, in the app target, with tests on a fixture ZIP; refuse
   anything else with a plain sentence). The picker also takes one or several CSVs.
4. **The screens**, in the design system's look: Settings → iCloud & data → "Import from Todoist…" beside
   "Import JSON…" (iPhone, iPad and Mac). The file picker; then a preview page or card: each project and where it
   goes (new Group, existing Group, Inbox), tasks, checklist lines, labels to be made, repeating tasks, dates not
   understood (a list one can open), already in HITList (skipped); "Import N tasks"; progress; then a toast and
   the page showing "Undo last import". A first line on the page says how to get the file out of Todoist, as a
   path. Errors in plain words (not a Todoist file; nothing to import).
5. **The write**, through the same functions the app uses to make tasks (so reminders, ordering and the snapshot
   behave), in batches with one save each so a few hundred tasks do not freeze the list; the sync bolt and the
   mirror are left alone (never poke them).
6. **Tests and a way to see it**: a Debug launch argument that opens the preview on a bundled fixture
   (`-todoistImportFixture`), since a file picker cannot be driven; a UI test that imports the fixture, checks the
   lists, runs it again (nothing doubles) and undoes it.

## Ownership
New files in `HITListCore/Sources/HITListCore/` named `Todoist*.swift` and their tests, new `HITList/Services/Import/*`,
new `HITList/Views/Import/*`, `Views/Settings/DataSettingsGroups.swift` (`ExportImportGroup`: the two rows) and
the Mac's data section only if the row is not shared, new `HITListTests/Todoist*Tests.swift`, a UI test file of
your own, fixtures under the tests' folders. `project.yml` only if a new folder needs listing (say so). Read but do
not edit: the models, `TaskActions`, the quick-add parser and date readers (if one of them needs a change, say
which and why, and make it in a file of your own that wraps it). Not yours: `ICloudSettingsGroups.swift`
(`ICloudDataPage` composes the page: your rows live inside `ExportImportGroup`, so that file needs no change), the
sync files, the calendar (136), Settings' other pages, companions, `scripts/`, `dev/`, `CHANGELOG.md`,
`WhatsNew.swift`, the What's New pin.

## Done (report due 22:00 Eastern)
Core first (`cd HITListCore && swift test`); boot your one simulator (`HITList-137`) only after 20:55. The
fixture imported, re-imported and undone on the iPhone simulator and on your Debug Mac app
(`HITLIST_STORE_SUFFIX=s137`, sync off), pictures of the preview and the result; all three suites green and your
UI class. The report COMMON asks for, with: the Todoist pages you read; the exact steps George takes in Todoist
and in HITList, as click paths; what does not come across (completed tasks, comments' attachments, assignees,
reminders, filters) said plainly; the choices he might reverse (sections as labels, sub-tasks with dates as
tasks, the duplicate rule).
