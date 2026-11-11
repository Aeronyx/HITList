# HITList roadmap

What is being built now, what comes next and what is parked. The supervisor rewrites this file at the start and end
of each round; delegated sessions never edit it (their rows conflicted at every merge). What shipped, release by
release, is in `CHANGELOG.md`; how each round ran is in `dev/briefs/COMMON.md`; George's standing decisions are in
`dev/SUPERVISOR.md` §7. Rewritten 2026-11-10: the file had grown a row per brief (history is in git before that date).

## Now: 0.9.3 (round 19, 2026-11-11, overnight)

| Brief | What | Status |
|---|---|---|
| 82 `time-zones`, 92 `day-anchor-review` | A date with no time is the same calendar day in every zone (stored at 10:00 UTC on its day; only a date this device can vouch for is rewritten, after a backup); everything catches up when the zone or the day changes | merged, awaiting release |
| 83 `location-weather` | Weather on by default; the location asked once at first launch; the place's time zone drives the companion's night and day | merged, awaiting release |
| 84 `companion-routines`, 91 | Idle routines (a few seconds of life every 5 to 12 minutes), sky-bound gestures, snow that piles up, a hot-day sky; nothing drawn in the air | merged, awaiting release |
| 85, 87, 88, 89 | A companion for every theme: Posy (Rosé, in Pip's place), Mallow (Mocha), Smudge (Graphite), Tuck (Moss), Glim (Tokyo Night) beside Nod, Quill and Hush | merged, awaiting release |
| 86 `settings-tidy` | Settings as one short screen and pages, Appearance second, every option in one home; a companion on each theme's swatch | merged, awaiting release |
| 90 `share-extension` | "Add to HITList" from the share sheet, through an outbox the app drains | merged, awaiting release |
| 93 `qa-sweep` | Every screen on four devices looked at; seven plain defects fixed, the rest listed for George | merged, awaiting release |
| 94 `accessibility` | VoiceOver wording for rows, tabs, switches, chips, cards and Settings; the Mac by keyboard; hit targets (the Mac's sync bolt); the system's audit as an on-demand UI test | merged, awaiting release; the audit passes on a fresh iPhone 17 simulator and runs on demand |

## Next (in this order unless George says otherwise)

1. **George's answers to the sweep's findings** (`93-qa-sweep/FINDINGS.md` in the round's notes): the large title's
   edge on the Pro Max and the Duo, the system date picker in Review Inbox and Upcoming's swipe, day headers written
   four ways, empty states in four styles, "Done" with three looks, the Mac Settings page's name shown twice. Each is
   a matter of taste or changes how a screen works, so none was touched.
2. **Widgets, third pass**: a Control Center "Add task", calendar events in the Upcoming widget, an "Add task"
   widget.
3. **The Mac window's shape on macOS 27.** Since 0.9.0 (21) the app draws its own sidebar rows, selection and toolbar
   controls; whether the sidebar column floats (26) or sits flush (27) is still the system's. Owning it means our own
   split view and top bar. Decide after a friend's screenshot on macOS 27.2 (still owed).
4. **Accessibility with a person, and the audit in the ordinary run.** Round 19 wrote the labels and the audit
   (`TEST_RUNNER_HITLIST_AUDIT=1`; 9 tests pass on a fresh iPhone 17 simulator, every one of its 404 findings
   excluded with a written reason). Wording and order need someone who uses VoiceOver; Full Keyboard Access on the
   Mac was never switched on (toolbar buttons, the board's cards, Flipboard tiles and Settings controls are not
   reachable by Tab without it); and the audit joins the ordinary UI run once it has passed at night and on a
   second device size (its exclusions name positions on the screen).
5. **Shared Tasks with two Apple accounts**, tested with a friend (untested since 0.7.1). A day a friend's 0.9.2
   wrote in another zone shows as before until their device updates.
6. **The share extension on a real Mac**: Safari's Share menu was never seen (macOS offers a new share extension
   only once it is switched on in System Settings); pickers for a Group and a date on the card.
7. **The Mac's task list.** It is still the system's `List`: a completed row's gap closes in one frame and the
   completion flash snaps, where the iPhone eases both (brief 75's audit). Drawing our own rows there, as the sidebar
   does since 0.9.0 (21), fixes both and removes the last system-drawn selection.
8. **Companions in nested screens by theme**, as George described, and more skies if he wants them (wind, fog, a
   cold snap).
9. **A user's own companion.** Extras → Companions → "Choose your own…", a sprite sheet from Files, the way the
   completion sound already takes a file. Characters other people own can live on someone's own device this way; the
   app and this public repository ship only original ones.
10. **The first-run day pass after the first frame**: it runs inside the app's start-up (6.8 s for 20,000 tasks;
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
