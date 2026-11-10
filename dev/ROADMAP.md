# HITList roadmap

What is being built now, what comes next and what is parked. The supervisor rewrites this file at the start and end
of each round; delegated sessions never edit it (their rows conflicted at every merge). What shipped, release by
release, is in `CHANGELOG.md`; how each round ran is in `dev/briefs/COMMON.md`; George's standing decisions are in
`dev/SUPERVISOR.md` §7. Rewritten 2026-11-10: the file had grown a row per brief (history is in git before that date).

## Now: 0.9.1 (round 17, 2026-11-10)

| Brief | What | Status |
|---|---|---|
| 74 `widgets` | Today, Upcoming and Flipboard widgets on iPhone, iPad and the Mac; the app's first extension | in progress |
| 75 `motion-polish` | An audit of everything that moves (cards, pickers, tabs, rows, small controls), and fixes | in progress |
| 76 `companions` | Two or three original pixel creatures in quiet corners, with idle loops and a rare flourish | in progress |
| 77 `calendar-events` | Today's and the week's calendar events beside the tasks, read-only and off by default (the last open item of the original list, #8) | in progress |
| 78 `steady-bolt` | The sync bolt keeps still while status is green and shows work or trouble only when it has lasted; a sync blip after an update no longer reads as an alarm | in progress |

## Next (in this order unless George says otherwise)

1. **Share extension.** "Add to HITList" from any app's share sheet (a link, selected text) on iPhone and the Mac.
   With widgets it is what the App Group store was moved for on 2026-10-27; it reuses the widget round's extension
   setup.
2. **Widgets, second pass** after George has lived with them: completing a task from the widget, Lock Screen and
   Control Center pieces left out of the first pass, calendar events in the Upcoming widget.
3. **The Mac window's shape on macOS 27.** Since 0.9.0 (21) the app draws its own sidebar rows, selection and toolbar
   controls; whether the sidebar column floats (26) or sits flush (27) is still the system's. Owning it means our own
   split view and top bar. Decide after a friend's screenshot of 0.9.0 (21) on macOS 27.2.
4. **Accessibility pass.** VoiceOver and Full Keyboard Access on the custom pieces: the Mac sidebar rows, the cards
   and pickers, the Flipboard's switches, the companions (hidden from VoiceOver).
5. **Shared Tasks with two Apple accounts**, tested with a friend (untested since 0.7.1).
6. **iPad and iPhone Duo check** of Switchboards, widgets and the sidebar's swipe to delete.
7. **A user's own companion.** Extras → Companions → "Choose your own…", a sprite sheet from Files, the way the
   completion sound already takes a file. Characters other people own can live on someone's own device this way; the
   app and this public repository ship only original ones.

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
