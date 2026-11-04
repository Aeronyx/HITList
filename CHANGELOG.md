# HITList changelog

One section per version. `scripts/release.sh --version X.Y.Z` refuses to run until the version has a
section here, then stamps the heading with the build number and date. Builds within a version are
TestFlight iterations; the heading lists the last build that shipped it.

## 0.6.0

George's notes on build 15 and his backburner list, in eight sessions: the Mac board's inline add, the
profile in the corner, quick-add polish, sync and profile hardening, a Claude connector, Siri and Shortcuts,
holidays, and the iPhone Duo.

- Mac and iPad Upcoming board: "+ Add task" on a day opens a small add card right in that day's column, with
  the cursor already in it. Add one task after another; Esc or × closes it and asks before throwing away
  typing. Every Mac quick add (toolbar "+", ⌘N) starts with the cursor in the task name.
- Your profile sits top-left: at the top of the Mac and iPad sidebar (picture and name, with a menu for
  Account settings, Settings and the iCloud state) and at the top left of Browse on iPhone.
- iPhone tabs: Inbox · Today · Upcoming · Flipboard (Flipboard back on the right).
- Quick add: the pointing hand over highlighted words on the Mac; a phrase you switched off lights up again if
  you delete it and type it again; "!15mb" stays plain until the task has a time (a reminder picked from the
  chip waits on the chip). In the task editor, × and Esc ask Discard when you have typed something.
- Claude: on the Mac, Settings → Claude → Allow Claude lets Claude Desktop and Claude Code list, add, complete
  and edit your tasks while HITList is open (a small helper inside the app, reached only by HITList; no server).
  Choose what Claude sees: everything except tasks labelled @private, or only tasks labelled @claude. Copy for
  Claude on both platforms copies the allowed tasks as JSON. Setup guide at aeronyx.github.io/HITList/claude.
- Siri and Shortcuts: "Add a task in HITList" (spoken the way you type, "Buy milk tomorrow 5pm p1 #Home"),
  "What's on my HITList today", Complete Task, and Open Today / Inbox / Upcoming, from Siri, Shortcuts or the
  Action button.
- Holidays: completing a task throws snow dust at Christmas, fireworks on July 4th and New Year's, hearts,
  bats, leaves and clovers on their days, with a tiny seasonal glyph on the "+". Once in a long while, a sky
  whale swims by. Settings → Delight → Holiday touches and Rare surprises.
- One device, two Apple accounts: switching accounts clears the previous person's open card, Undo toast,
  reminders and badge, and sets their backups aside; nothing in iCloud is touched. Settings → iCloud and
  Account show the same sync line; the profile picture is decoded once; saving the same name twice writes
  nothing; duplicate tidying no longer collides with a download in progress; the sync log records the time
  to first screen.
- Privacy policy: new sections on the Claude connection and on Siri.

## 0.5.0 — build 15, 2026-11-04

George's notes on build 14, in five sessions: an account and profile for friends on TestFlight, a privacy
policy, the iPhone tabs, a roomier editor, quick-add highlights, and a board for the Mac's Upcoming.

- Settings → Account: your name and picture, synced to all your devices through iCloud, and a plain answer
  to "which iCloud am I on?" (signed in, signed out, restricted), how to sign out, and how to delete your
  data. Delete profile removes only the name and picture. Your account is the Apple account the device uses
  for iCloud; there is no separate login.
- Privacy policy at aeronyx.github.io/HITList/privacy, linked from Settings → About. Short version: HITList
  collects nothing. Copy diagnostics says whether a profile exists and has synced (never its name).
- iPhone tabs: Inbox · Today · Flipboard · Upcoming. The magnifying glass at the top right opens Browse; on
  Browse the gear there opens Settings. Browse shows who you are at the top (or "Add your name") and ends
  with Completed and Settings. A screen's old "…" items (Review Inbox, Jump to today) are at the bottom of
  its view-options menu; on Flipboard, long-press the sound button for Add Switch…. Flipboard can be the
  start screen; a saved Browse start screen opens on Today.
- The task editor opens taller (sub-tasks and Confirm fit without scrolling), the Confirm pill is bigger
  (76 × 48 on iPhone, on both Add task and Edit task), and the "Created …" line moved to the bottom of the
  editor's "…" menu.
- iPhone: the keyboard has a plain return key and only the Confirm pill saves a task; Return in a title
  does nothing. Swiping the editor down after typing asks Discard; with nothing typed it just closes.
- Quick add: type a second date, time, priority, Group, repeat or reminder and the later one wins; tap it off
  and the earlier one comes back ("jan 6 zach fox in a month" → tap "in a month" → Jan 6). Same-coloured
  highlights next to each other read as one box ("tom 4"), and one tap turns the whole box back into text.
  A reminder picked before the task has a time lights up at once and counts as soon as a time is added.
- Mac (and iPad at full width): Upcoming is a board, an Overdue column then seven days side by side, each
  with its count and its own scrolling. ‹ › move a day, Today comes back, the month title jumps to any day.
  Drag a task to another day and it keeps its time and its repeat's time; Overdue's Reschedule moves every
  overdue task; each day's "+ Add task" adds on that day. iPhone keeps its list.
- The sync bolt stays grey, not red, for someone who has never signed in to iCloud; a task added from an
  Upcoming day with a time and a priority or label lands on that day, not today.
- Schema V4 adds `Profile` (additive; deployed to CloudKit Production before this build).

## 0.4.1 — build 14, 2026-11-03

George's notes on build 13, split across three sessions: sub-tasks, a real task editor, quick-add time
phrases, and the feel of taps, toasts and buttons.

- Sub-tasks: a checklist inside any task, one level deep. Add them from the quick-add "+" (Subtasks: one
  line each, Return for the next) or in the editor; rows show "2/5". Completing a task ticks its open
  sub-tasks and Undo reopens them; a repeating task's next occurrence starts with its checklist open.
  Sub-tasks never appear as rows of their own and are not counted in Group and label counts.
- The task editor is rebuilt: a title card with Group and date rows, value pills for Description,
  Priority, Reminder, Labels, Repeat, Deadline and Location, the Sub-tasks checklist, and one Confirm pill
  that saves everything typed and closes in one tap (Return in the title, ⌘Return on the Mac). × or Esc
  closes without saving unsaved typing.
- Quick add understands "in 10 minutes", "in two hours", "in half an hour", "in three days", "in a week",
  "in a month" (number words one to twelve); the phrase is one highlight, tap to keep it as text.
- Reminder shortcuts (`!15mb`, `!1h`, `!at`) only count, and only light up, when the task has a time; a
  bare "!" or "!0mb" stays in the title.
- Repeating tasks keep their exact time across the clock changes: the rule now stores the time of day
  and each occurrence is rebuilt from it.
- Tasks with the same priority and date stay in the order you added them.
- The suggestion pills under the quick-add title are gone.
- A quick-add card reopened after its Group was renamed adds to that Group; one whose Group was deleted
  adds to the Inbox.
- iPhone: one light tap when you press "+", confirm a task, or complete one (it used to tap twice on
  completion); the "+" is larger; task titles are a step smaller and a pixel tighter.
- The Undo toast is one big button, 48 pt tall and sized to its text; on the iPhone it sits beside the
  "+", on the Mac and iPad at the list's bottom-right corner; swipe it away to keep the completion.
- Mac: the window comes back at once after you close it and click the Dock icon (or ⌘Tab back); the
  toolbar "+" is smaller.

## 0.4.0 — build 13, 2026-11-02

The first beta for friends. Two review passes on the core, each change with a test that failed first, then
George's decisions on dates, times, taps and drafts.

- iCloud sync keeps a record. Settings → iCloud shows which CloudKit environment and build channel this
  copy syncs with ("Production · TestFlight build 13") and has a Sync log: every setup, import, export,
  push, account and network change with timings and full error details, filterable to errors, with Copy
  and Share. A watchdog records an error when a local change has no export within 5 seconds or a push no
  import within 5 seconds, and when a sync request has hung for a minute; after two minutes the bolt is
  struck through, "Sync paused: stuck", and Settings offers Relaunch on the Mac (a first import on a new
  device gets ten minutes). This is the state that held the Mac's changes back for 16 hours on Nov 1.
- Builds run from Xcode keep their own store, reminders and backups, apart from the TestFlight app's; a
  TestFlight or App Store build is never mistaken for one.
- Reminders no longer fire for tasks completed, deleted or moved from a list. Complete on a stale
  reminder no longer skips a repeating task's next occurrence; Snooze no longer undoes a move.
- Daily backups and Export JSON now carry reminder offsets, deadlines, locations and Flipboard state;
  old backups still restore.
- A store that cannot be opened no longer crashes the app at launch: it runs on an empty in-memory copy,
  leaves the file alone, says so, and offers Reset. A cache reset acts only on the store that asked for it.
- Typing a very long number in quick add ("!9999999999999999d", "every 99999999 days") no longer crashes.
- Sticky drafts keep the location and deadline picked from "+". Clearing a task's title in the popout
  puts the original back instead of saving a task with no title.
- About → Copy diagnostics and Check iCloud report the right CloudKit environment on every build.
- iPhone: the quick-add title has standard autocorrect and sentence capitals (it had autocorrect off).
- Dates and times read the way George does: monthly and yearly repeats keep their original day (Jan 31,
  Feb 28, Mar 31; Feb 29 in leap years), a repeating task typed after its time today starts at its next
  occurrence unless a date was typed, and times are 24-hour unless am or pm is typed ("tom 13" is
  tomorrow 13:00, "at 5" is 05:00). Picking "Every month" again keeps the day.
- Quick add: tap or click a highlighted token to switch it off and keep the words as plain text ("Call
  Tom" with no date); highlights are rounded like buttons. "Sticky" now means only that an open card
  with text survives app switches and a kill, reopening on launch in its own list; nothing is ever restored
  into a fresh card, and every way of closing clears it. Each build keeps its own open card.
- Completing is final until Undo: a second tap on a row still animating does nothing; undo is the toast
  or the Completed list. Every iPhone toast is drawn above the island on every screen size. A task
  popout closes by itself when the task is deleted on another device. The iPhone push handler finishes as
  soon as its import lands instead of waiting 25 seconds.
- Two review passes over the merged work: highlights never sit on the wrong words of a long title, the
  Mac's ⌘N over an open panel starts a fresh card, a pasted line break becomes a space, typing parses the
  title once per keystroke, and tapping away asks "Discard?" whenever the card holds anything.

## 0.3.5 — build 12, 2026-11-02

- iPhone lists look like the Mac's: rows flat on the background with hairline separators, headers over the
  checkboxes; no more inset cards on Today and the Inbox. The undo toast rises above the island instead of
  behind it.
- Completing a task is snappier: the checked row leaves after 380 ms instead of 600.
- Quick-add: the confirm pill is hollow and faded until there is a title, then fills with the accent.
  Tapping away from a card with text drops the keyboard and offers "Discard" in a bubble above it; any
  other tap brings the keyboard back. Drafts are sticky: the text survives closing the card, backgrounding
  and relaunching, until the task is added or discarded (`QuickAddDraftStore`).

## 0.3.4 — build 11, 2026-11-01

- Task rows measure like Todoist's (`ListMetrics`: 12 pt above the title, 10 below the second line, on
  both platforms; Compact rows trims it), every row the same height unless a long title wraps. Titles are
  capped at 500 characters; a description shows its first line under the title.
- Mac: one line under a section header, not two; the toolbar "+" is back to build 9's.
- Mac: the lists' sidebar only fades under the Settings sections (it stays built), so nothing stutters.
- iPhone: after adding a task the card holds still and fades while the keyboard drops; nothing rides the
  keyboard or re-lays out on the way.

## 0.3.3 — build 10, 2026-11-01

- Task rows are slimmer and all the same height, with the same air above and below (`ListMetrics`), on
  both platforms; Compact rows trims it further. The "P1"/"P2" badge is gone: the checkbox's colour is
  the priority.
- Section headers ("Overdue", "Nov 1, Sunday", "Priority 1") share one type size and one padding on
  every list, so the gap to the first row is the same under every header; the Inbox's priority headers
  are no longer caption-sized.
- Mac: Settings uses the window's sidebar for its sections, System Settings style, with Back on top; the
  sidebar column no longer collapses and reopens, which stuttered.
- The "+" oval is a little shorter on both platforms; the sync bolt sits nearer the two controls.

## 0.3.2 — build 9, 2026-11-01

- The sync bolt says its state by shape: filled when synced, hollow and breathing while syncing, struck
  through when it cannot sync or has not synced in a day. Each theme has its own pastel bolt colour
  (Slate's is a soft yellow); errors and sign-out turn it red.
- Mac: Settings is a full-window page with its own Back; the sidebar slides away while it shows. ⌘,, the
  gear, the "…" and the bolt all open it. Sections: General (with every keyboard shortcut), iCloud,
  Reminders, Completing tasks, Appearance (theme previews, Reduce effects, Compact rows), Data, About.
- Flipboard: a dashed switch-shaped tile with a big + adds a switch, in the grid itself.
- Inbox: one section per priority, Priority 1 first.
- Upcoming: the filter-lines menu holds Show overdue and Days shown (2 weeks, 1 month, 2 months); Jump to
  today moved into the "…".
- Mac: the quick-add title no longer draws a grey box behind the words; the Add task row reads at body size.
- iPhone: the theme swatches in Settings wrap to two rows (they overflowed the sheet in 0.3.1).

## 0.3.1 — build 8, 2026-11-01

- Sync status is a small bolt in the toolbar's empty space, soft accent when synced, breathing while it
  syncs, slashed grey offline, orange when it needs attention; the cloud icon in the pill is gone.
- Every screen has two controls beside it: Upcoming gets Jump to today, Browse gets New… (Group, label,
  filter), the Flipboard gets Add switch; the "…" on the Mac now holds Settings… and the version too.
- iPhone: the quick-add card is put away in one motion, fading as it rides the keyboard down.
- Four more themes: Nord, Tokyo Night, Mocha, Rosé.
- Release artifacts move to build.noindex so Spotlight stops offering stale copies of the app.

## 0.3.0 — build 7, 2026-11-01

- Mac: every chip in the quick-add and task popouts opens a card drawn inside the window (no more system
  popovers hanging past the edge): a HITList month calendar, a time row that reads "9am", "17:30" or
  "noon", presets (Today, Tomorrow, Next week, Weekend, No date), a reminder card with offsets and the
  fire time, and the Priority, Group, Labels, Repeat, Deadline and Location cards. Escape and a click
  outside close just the card; Tab moves into it; arrows and Return pick a day.
- Sync status is a small cloud icon at the left of every screen's toolbar (tap for Settings) instead of
  the Mac sidebar's footer line and the dot on the "…".
- Mac: the toolbar "Add task" is a proper prominent capsule; the card's confirm button is an outlined
  capsule so the two no longer look alike.
- iPhone: adding a task puts the quick-add card away (sliding back down behind the keyboard); lists show
  no "Add task" row, only the oval "+", and an empty list says "No tasks" (or "All clear for today",
  "Nothing due") in grey; every list leaves room for the floating island, so the last row (Browse →
  Settings) is reachable again.
- Task rows: the second line is always laid out, so rows with and without dates line up; the Group sits
  at its trailing end with its colour dot after the name.
- Mac: the toolbar "Add task" is the same accent oval as the iPhone's; the quick-add title no longer shows
  a grey text-view box when focused; Inbox review ("Review Inbox…") and the Flipboard's actions live in
  the "…" menu on every platform; the review sheet's Done buttons use the design system; the popout
  panel's shadow is flattened before animating.

## 0.2.0 — build 6, 2026-10-31

- Quick-add title one step larger than the list text (14 pt was too small): Inter 20 bold on iPhone.
- iPhone chrome: the tab bar is a floating island (a 64 pt capsule inset from the edges, lists scroll
  under it), the oval "+" sits above its right end, and every screen has the filter-lines view options
  and a "…" menu beside it with the screen's actions, Settings… and the version; a 6 pt sync dot on the
  "…" turns green when everything has synced and pulses once when a sync lands.
- Liquid Glass on iOS 26 / macOS 26: the island, the "+", the quick-add card, sheet headers, the segmented
  control's highlight and chip hover; the slate look stays on iOS 18 and under Reduce Transparency or the
  new Reduce effects setting.
- Four dark themes (Slate, Graphite, Midnight, Moss) in Settings → Appearance, switching live.
- Motion roles (quick, standard, enter, exit, emphasis, celebrate): nothing outside the completion check
  lasts over 250 ms; crisper check pop; completed rows slide away; the undo toast rises and falls.
- Settings: Start screen, Week starts on (Upcoming, "next week" in quick add and rescheduling), app icon
  badge, Confirm before deleting (one dialog for every delete path), Default reminder offset, Morning
  summary notification, notification authorization and test, Check iCloud round trip, Copy diagnostics,
  What's new, Version.
- Releases: `scripts/release.sh --version` with this changelog; preflight tests before any upload.

## 0.1.0 — builds 1–5, 2026-10-27 to 2026-10-31

- Build 1: first TestFlight build. SwiftUI multiplatform, SwiftData + CloudKit private database.
- Build 2: dedupe for seeded records, versioned schema, App Group store, sync resilience, reminders, CI.
- Build 3: filter language with autocomplete and editor, completion delight and sounds, Upcoming, Inbox
  polish, Task Flipboard.
- Build 4: design system (buttons, toggles, chips, fields, sheet chrome), task popouts, floating "+".
- Build 5: Inter typeface, schema V2 (reminder offsets, deadline, location, Flipboard charge), iPhone
  tabs (Inbox / Today / Upcoming / Browse), oval quick-add card with "+" options and `!15mb` reminders,
  Flipboard long-press menu, faint-green lamp and charging switches, aligned task rows.
