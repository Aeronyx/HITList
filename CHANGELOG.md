# HITList changelog

One section per version. `scripts/release.sh --version X.Y.Z` refuses to run until the version has a
section here, then stamps the heading with the build number and date. Builds within a version are
TestFlight iterations; the heading lists the last build that shipped it.

## 0.2.1

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
