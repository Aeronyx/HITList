# HITList changelog

One section per version. `scripts/release.sh --version X.Y.Z` refuses to run until the version has a
section here, then stamps the heading with the build number and date. Builds within a version are
TestFlight iterations; the heading lists the last build that shipped it.

## 0.2.0

In progress. Planned for this version:
- Quick-add title a step larger than the list text (George: 14 pt was too small).
- Settings shows the version and build; preflight tests gate every upload (this file, `release.sh --version`).
- iPhone: floating island tab bar, "…" menu on every screen with Settings, tiny sync dot.
- Settings: more preferences, a notification test, sync confirmation.
- Sleeker motion, accent themes, Liquid Glass on iOS 26 / macOS 26.

## 0.1.0 — builds 1–5, 2026-10-27 to 2026-10-31

- Build 1: first TestFlight build. SwiftUI multiplatform, SwiftData + CloudKit private database.
- Build 2: dedupe for seeded records, versioned schema, App Group store, sync resilience, reminders, CI.
- Build 3: filter language with autocomplete and editor, completion delight and sounds, Upcoming, Inbox
  polish, Task Flipboard.
- Build 4: design system (buttons, toggles, chips, fields, sheet chrome), task popouts, floating "+".
- Build 5: Inter typeface, schema V2 (reminder offsets, deadline, location, Flipboard charge), iPhone
  tabs (Inbox / Today / Upcoming / Browse), oval quick-add card with "+" options and `!15mb` reminders,
  Flipboard long-press menu, faint-green lamp and charging switches, aligned task rows.
