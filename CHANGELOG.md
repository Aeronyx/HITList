# HITList changelog

One section per version. `scripts/release.sh --version X.Y.Z` refuses to run until the version has a
section here, then stamps the heading with the build number and date. Builds within a version are
TestFlight iterations; the heading lists the last build that shipped it.

## 0.3.3 — build 10, 2026-11-01

- Task rows measure like Todoist's (`ListMetrics`: 12 pt above the title, 10 below the second line, on
  both platforms; Compact rows trims it), every row the same height unless a long title wraps. Titles are
  capped at 500 characters; a description shows its first line under the title. The "P1"/"P2" badge is
  gone: the checkbox's colour is the priority.
- Section headers ("Overdue", "Nov 1, Sunday", "Priority 1") share one type size and one padding on
  every list, so the gap to the first row is the same under every header; the Inbox's priority headers
  are no longer caption-sized.
- Mac: Settings uses the window's sidebar for its sections, System Settings style, with Back on top; the
  sidebar column no longer collapses and reopens, and the lists' sidebar only fades under the sections
  (it stays built), so nothing stutters.
- iPhone: after adding a task the card holds still and fades while the keyboard drops; nothing rides the
  keyboard or re-lays out on the way.
- The iPhone "+" oval is a little shorter; the sync bolt sits nearer the two controls.

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
