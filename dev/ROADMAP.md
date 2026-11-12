# HITList roadmap

What is being built now, what comes next and what is parked. The supervisor rewrites this file at the start and end
of each round; delegated sessions never edit it (their rows conflicted at every merge). What shipped, release by
release, is in `CHANGELOG.md`; how each round ran is in `dev/briefs/COMMON.md`; George's standing decisions are in
`dev/SUPERVISOR.md` §7. Rewritten 2026-11-10: the file had grown a row per brief (history is in git before that date).

## Now: 0.9.6 (rounds 21 and 22, 2026-11-11 to 12)

0.9.5 (round 21, overnight) was prepared and not released: George looked at its pictures and sent it back before
dawn. Round 22 worked his notes in by nine; 0.9.6 carries both rounds.

| Brief | What | Status |
|---|---|---|
| 109 `button-back` | Button as 0.9.4 drew him, pixel for pixel, standing on the bar, with a mushroom's idles and no boot swinging; Button's and Nod's snow | merged, awaiting release |
| 110 `phase-cloth` | Phase redrawn as a little cloth ghost with eyes of its own, wholly on top of the bar; rain and snow pass through it | merged, awaiting release |
| 111 `gargle-dragon` | Gargle more of a dragon: a snout, reptile eyes, a closed mouth, smoke and an ember | merged, awaiting release |
| 112 `hush-quill` | Hush and Quill drawn with more care in the same poses; their snow | merged, awaiting release |
| 113 `glim-tuck` | Glim improved, his tail and its light out of the rain and snow; Tuck asleep with its eyes shut on their stalks | merged, awaiting release |
| 114 `card-insets` | Room around the words in quick add, the editor and every picker card; a test that measures it | merged, awaiting release |
| 115 `screen-insets` | Rows, the Flipboard, the switch card, Browse and Review Inbox on their edges and at even gaps | merged, awaiting release |
| supervisor | Three snow inks; "Pick a Group" on one line on an iPhone 16; the reminder card's times in two columns | merged, awaiting release |
| round 21 (103 to 108) | Idles that are each creature's own, the "behind the host" layer, names under themes, the iPhone Duo's outer and inner displays | merged, awaiting release |

## Next (in this order unless George says otherwise)

1. **George's eye, and his friend's, on rounds 21 and 22**: the eight creatures at real size (Phase and Gargle most
   of all) and the snow on them; quick add's chips on two or three lines; the Duo's outer display in the friend's
   hand (the title row's controls, the cards, the companion on the tab bar); whether the Duo's title should stay
   put while a list scrolls.
2. **The Duo's inner display, for real.** Nobody has seen it since October: Device Hub could not list the round's
   simulators (`killall -u "$USER" CoreDeviceService` in George's Terminal, then `108-duo-inner/unfold.sh`). Then:
   the system's bar column on its side, how sheets are sized there, Settings closing on a fold, the keyboard.
   **What happened to "Shave"** (round 20) is still open: Check iCloud… on each device names it.
3. **Widgets, third pass**: a Control Center "Add task", calendar events in the Upcoming widget, an "Add task"
   widget.
4. **The Mac window's shape on macOS 27.** Since 0.9.0 (21) the app draws its own sidebar rows, selection and toolbar
   controls; whether the sidebar column floats (26) or sits flush (27) is still the system's. Owning it means our own
   split view and top bar. Decide after a friend's screenshot on macOS 27.2 (still owed).
5. **Accessibility with a person, and the audit in the ordinary run.** Round 19 wrote the labels and the audit
   (`TEST_RUNNER_HITLIST_AUDIT=1`; it passed on a fresh iPhone 17 simulator, every finding excluded with a written
   reason; round 20 moved many screens, so rerun it). Wording and order need someone who uses VoiceOver; Full
   Keyboard Access on the Mac was never switched on; the audit joins the ordinary UI run once it has passed at
   night and on a second device size.
6. **Shared Tasks with two Apple accounts**, tested with a friend (untested since 0.7.1).
7. **The share extension on a real Mac**: Safari's Share menu was never seen (macOS offers a new share extension
   only once it is switched on in System Settings); pickers for a Group and a date on the card.
8. **The Mac's task list.** It is still the system's `List`: a completed row's gap closes in one frame and the
   completion flash snaps, where the iPhone eases both (brief 75's audit). Drawing our own rows there, as the sidebar
   does since 0.9.0 (21), fixes both and removes the last system-drawn selection.
9. **Quick add's guide**: tapping an example opens quick add with it typed (the card has no entry point that starts
   with text); the widgets' and the Duo's own shorter day forms follow the one formatter where they fit.
10. **Companions in nested screens by theme**, as George described, and more skies if he wants them (wind, fog, a
    cold snap); the Mac's companion idles only while HITList is the front app.
11. **A user's own companion.** Extras → Companions → "Choose your own…", a sprite sheet from Files, the way the
    completion sound already takes a file. Characters other people own can live on someone's own device this way; the
    app and this public repository ship only original ones.
12. **The first-run day pass after the first frame**: it runs inside the app's start-up (6.8 s for 20,000 tasks;
    real stores are small today), and an import that can restore the backup it takes.

## George's, no code needed

- App Store prerequisites when the public release is near: support URL, screenshots per platform, age rating.
- CloudKit schema deploys before a release that changes the model (the supervisor says so in bold).
- Side stores and old worktrees to delete by hand (listed in each round's hand-over).

## Parked

- The home-server backup (a design relic in `dev/DESIGN.md` §5; iCloud's private database is the store).
- CI that archives and uploads on a tag (`scripts/release.sh` does it locally in one command; CI runs the tests).
- Localisation (English only while the wording still changes every round).
- Collaboration beyond Shared Tasks, comments, boards, a right sidebar, light mode: decided against (§7).

## Shipped

Newest first; one line per release, details in `CHANGELOG.md`.

- **0.9.4**, 2026-11-11: a sync bolt that is filled only when iCloud has just confirmed it, and Check iCloud…;
  companions that idle every few seconds and sit on the "+"; Button, Phase and Gargle; the repeat menu and Custom…;
  "starting", weekday lists and the quick add guide; a calmer Flipboard card, drag and Duplicate; the Mac's Settings
  button and a sweep's eighteen items.

- **0.9.3**, 2026-11-11: a companion for every theme with idle routines and the weather shown on the creature; the
  location asked once; a date with no time kept on its day in every zone; Settings as one short screen and pages;
  the share extension; a sweep of every screen and an accessibility pass.

- **0.9.2**, 2026-11-11: companions that keep still, one per theme (four drawn), asleep at night, dressed for rain
  and snow through WeatherKit; widgets that check a task off and keep it ticked until iCloud has it.

- **0.9.1**, 2026-11-10: widgets (Today, Upcoming, Flipboard, Lock Screen); the motion audit and its repairs; two
  pixel companions, Nod and Quill; calendar events, off by default; the sync bolt keeps still.
- **0.9.0 (21)**, 2026-11-10: the Mac draws its own chrome for macOS 27; Switchboards and routine switches (schema
  V6); monthly and yearly repeats in quick add; swipe to delete in Browse; the bolt's coin spin; notes per build.
- **0.9.0 (20)**, 2026-11-08: Shared Tasks as one Group; the editor's title reads quick add; Mac sidebar search; the
  type scale; the bolt's slam; the switch card.
- **0.8.1** and **0.8.0**, 2026-11-07/08: Groups in the Inbox and Today, sorts, Review Inbox, Flipboard intervals,
  tab motion, shared tasks in the lists.
- **0.7.1**, 2026-11-05: the Friends build. Highlights on native text views, reminders from now (schema V5), Extras,
  the Claude connector off by default, Shared Tasks on its own container, tips, Spotlight, the profile menu.
- **0.6.0**, 2026-11-05: the Claude connector (MCP helper), Siri and Shortcuts, the Mac board's inline add,
  holidays and the rare sky whale, iPhone Duo layouts.
- **0.5.0**, 2026-11-04: account and profile (schema V4), the privacy policy, the four-tab iPhone shell with Browse
  behind the magnifying glass, the Mac Upcoming board.
- **0.4.1** and **0.4.0**, 2026-11-02/03: sub-tasks (schema V3) and the task editor, quick-add language, sync log
  and watchdog, the beta-readiness review, haptics and the Undo toast.
- **0.3.x**, 2026-11-01/02: Mac pickers as in-window cards, the Mac Settings page, the sync bolt, row metrics.
- **0.2.0**, 2026-10-31: the design system, Inter, popouts and the quick-add card, the iPhone tab shell, themes and
  motion roles, Settings v2, schema V2.
- **0.1.0**, 2026-10-27/28: the first TestFlight build and the foundations below.

## Foundations (2026-10-27/28, all done)

The original list, in the order it was worked: git baseline and the one-command release script; multi-device dedupe
with stable seeded ids (`Deduplicator`, `SeedIdentity`); the versioned schema and its additive-only rules
(`SchemaVersions.swift`); the store in an App Group container (for widgets, intents and a share extension); sync
resilience (account changes, reset and re-download, daily local backups, the status row); reminder robustness
(reschedule on import, actions, time zones, the 64-notification cap); app tests and GitHub Actions CI; the filter
language; the Flipboard. Item 8 of that list was "Calendar (EventKit), themes, preferences": themes and preferences
shipped in 0.2.0, the calendar overlay is brief 77.

## Decisions log

- 2026-10-26: iCloud private database only; home server stays a design relic (DESIGN.md).
- 2026-10-26: CloudKit.framework linked explicitly (macOS 26 sandbox bug, Apple forums 835400).
- 2026-10-26: `com.apple.developer.icloud-container-development-container-identifiers` must never be
  in the entitlements; App Store Connect rejects uploads carrying it (errors 90045 / 90285).
- 2026-10-28: Filter language skips Todoist's collaboration terms (`assigned`, `added by`, `shared`,
  `workspace`), `subtask`, `/sections` and `deadline:`: HITList is single-user and had no sub-tasks,
  sections or deadlines, so they get explanatory errors instead (sub-tasks arrived in 0.4.1, brief 32,
  but never as rows of their own, so the filter term stays out). `,` stays an AND (one list per view)
  rather than Todoist's "separate lists".
- 2026-10-31 (round 3): "Group" is the user-facing word for Project; the model and `#name`/`project:` syntax
  stay. Inbox = every dated task plus undated tasks with no Group; undated tasks in a Group show only inside
  it (notes). Today and Inbox sort priority-then-due; saved filters keep due-then-priority. Due colours:
  today green, tomorrow orange, later purple, overdue red (`HITColor.due`). Inter ships as six static 18 pt
  cuts because iOS resolves only a variable font's default instance by PostScript name.
- 2026-10-31: schema V2 deployed to CloudKit Production by George after the Development push; build 5 (0.1.0) is the first build that writes the new fields.
