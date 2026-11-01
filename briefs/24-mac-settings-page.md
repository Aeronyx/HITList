# Brief 24: a Mac Settings page inside the window

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first (especially "Where things stand" and the
round-6 ownership), then `HITList/Views/SettingsView.swift`, `HITList/Views/Settings/*`,
`HITList/HITListApp.swift` (the `Settings` scene), `HITList/Views/ContentView.swift` (`SplitContent`,
`SidebarItem`, `ListScreen`), `HITList/Views/SidebarView.swift`, `HITList/Views/Tabs/ScreenMenu.swift`
(`screenChrome`, `openAppSettings`), and `HITList/Support/DesignSystem/README.md`.

## Why (George, 2026-11-01, on the Mac)
"We need to make vast improvements to the settings menu(s) in the Mac app, the popup with an X in the
corner feels lazy and outdated, there should be a dedicated settings page/settings icon button with a sleek
UI and useful features." The Mac's standard Settings window (⌘,) is what they mean by the popup.

## Files you own
`HITList/Views/SettingsView.swift`, `HITList/Views/Settings/*` (all of it; the Appearance section is
yours now too), new files under `HITList/Views/Settings/Mac/`, `HITList/HITListApp.swift` (the Settings
scene and the `appSettings` command only), `HITList/Views/ContentView.swift` (adding the `.settings` sidebar
item and its screen), `HITList/Views/SidebarView.swift` (the gear and the new item), the `openAppSettings`
function in `HITList/Views/Tabs/ScreenMenu.swift` (nothing else there), `HITListTests/SettingsTests.swift`,
new `HITListTests/MacSettingsTests.swift`, and the ROADMAP row named below. Not yours: `Theme.swift`,
`HITTokens.swift`, the Services, `Models.swift`, `project.yml`, `Popouts/*`, `Tabs/MobileShell.swift`.

## Know before you start
- Settings content today: `SettingsView.groups` builds `HITGroup`s (General, iCloud Sync, Danger, Export &
  Import, Backups, Reminders, Completing Tasks, Appearance, About) shared by the iPhone sheet and the Mac
  window. Keep the iPhone sheet exactly as it is; this brief is the Mac (and iPad, if it falls out).
- The Mac shows `SplitContent`: `SidebarView` (selection: `SidebarItem?`) and `ListScreen(item:)` in the
  detail column. The sidebar has a gear at the bottom that calls `openSettings()`, and the "…" on every
  screen has Settings… → `openAppSettings()` → `openSettings()` on the Mac. The sync bolt's tap does the same.
- `HITListApp` has a `Settings { SettingsView() … }` scene on macOS, which is the window to replace, and
  `.commands { NewTaskCommands() }`.
- Design system: `HITGroup`, `HITMenuRow`, `HITSegmented`, `HITToggleStyle`, `HITChip`, `HITField`,
  `HITButtonStyle`, `hitGlass`, `HITMotion` roles; type via `HITType`; the current theme via `Theme.*`.
  Eight palettes exist (`ThemePalette.all`), with swatches in `AppearanceSettingsSection`.

## Task, in commits
1. **A `.settings` destination.** Add `case settings` to `SidebarItem`; `ListScreen(item: .settings)`
   shows the new `MacSettingsPage` in the detail column. The sidebar's gear selects it (no sheet, no
   window); so do ⌘, (replace the `appSettings` command group with a button that sets the selection; a
   small `@Observable` `SettingsRouter` in the environment, or a notification, is fine), the "…" menu's
   Settings…, and the sync bolt. Remove the `Settings` scene on macOS. iPhone keeps its sheet.
2. **`MacSettingsPage`.** Two columns inside the detail area: a 200 pt list of sections on the left
   (General, iCloud, Reminders, Completing tasks, Appearance, Data, About), each with an SF Symbol in a
   small tinted square and a one-line caption; the chosen section's content on the right in a scroll view
   at most 620 pt wide, with a large Inter title, the existing `HITGroup`s re-flowed (split the current
   `groups` into one view per section so both the iPhone sheet and this page use the same pieces).
   Selection remembered across launches (a `Preferences` key in your own `extension Preferences` file).
   Hover and selection use `HITMotion.quick`; the section list uses `hitGlass` for its selection pill
   when effects are allowed, slate otherwise.
3. **Useful features** (each its own commit, each with a test where there is logic):
   - **Keyboard shortcuts** section under General: a table of every shortcut the app has (⌘N, ⌘⇧C,
     ⌘←/⌘→, Esc, Return, the Process-mode keys), read from one static list that the commands also use.
   - **Data** section: counts of tasks (open, completed, overdue), Groups, labels, filters; store size
     on disk; "Show store in Finder"; Export/Import and Backups move here from their own groups.
   - **iCloud** section: the existing status line, Check iCloud…, Details; add "Last change" with the
     phase (import/export) and a tiny 7-day sparkline of changes per day if `CloudSyncMonitor` can
     supply counts cheaply (if not, skip the sparkline and say so).
   - **Appearance**: the theme swatches at 56 pt with the theme's accent as the ring, a live preview
     card (a fake task row and chip in the chosen palette), Reduce effects, and "Compact rows" (a
     `Preferences` key; `TaskRow` belongs to no one this round, so store the key and list it as pending).
   - **About**: version, build date (from the bundle's executable modification date), Copy diagnostics,
     What's new inline (not a sheet) and a "Changelog" link to the GitHub release.
4. **Tests.** `MacSettingsTests`: the sections list is stable (ids and order), each section view renders
   (`ImageRenderer`, as `DesignSystemTests` does), the shortcuts list has no duplicate keys, Data counts
   from an in-memory container, the remembered selection round-trips. Existing `SettingsTests` green.
   `scripts/test.sh core macos` after each commit; `ios` before the last.
5. **ROADMAP.** Add one row to the second table: "Mac Settings page (in-window, sections, shortcuts, data,
   previews)" with status and what you verified.

## Verify running
Build and run the Mac app; describe in words: gear → page, ⌘, → page, "…" → page, bolt → page; each
section at the window's minimum size (760 × 560) and at 1200 wide; theme switch updates the preview and
the whole window. You cannot screenshot the Mac; your description and the tests are the record. Confirm
the iPhone 17 simulator's Settings sheet is unchanged.

## Report
What changed per commit; test counts before and after; the Mac description; the branch name; anything
George must decide (section names, whether Data should also offer "Delete completed tasks older than…",
which you should NOT build this round).
