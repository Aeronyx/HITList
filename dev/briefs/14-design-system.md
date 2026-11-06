# Brief: HITList design system (no default controls)

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first.

## Why
George: "We need a button and switch UI set that doesn't use your defaults so this doesn't feel like AI
slop. Elements such as the Due date and Time sliders and the Cancel and Save buttons on the Filters
popout are unacceptable defaults. The plus icons are also still too far to the right. The eye in the
top right is scarily large." Todoist is the reference for density and restraint; HITList's identity is
the dark slate palette in `Theme.swift` with the `#6C9EFF` accent and the P1-P3 colours in `Formatting.swift`.

## Files you own
New `HITList/Support/DesignSystem/` (all components), `HITList/Views/FilterEditorView.swift`,
`HITList/Views/ProjectEditorView.swift` (also holds `LabelEditorView`), `HITList/Views/SettingsView.swift`,
`HITList/Views/Delight/DelightSettingsSection.swift`, `HITList/Views/SidebarView.swift`, and in
`HITList/Views/TaskListView.swift` ONLY the `.toolbar { … }` block. New test files in `HITListTests/`.
Do not touch `TaskDetailView.swift`, `QuickAddBar.swift`, `TaskRow.swift`, `ContentView.swift`,
`UpcomingView`, Flipboard or Inbox files: a following session (`briefs/15-task-popouts.md`) rebuilds
those on top of your components, so your API has to be clean and documented.

## Task, four commits
1. **Tokens + primitives** (`DesignSystem/HITTokens.swift`, `HITButtonStyle.swift`, `HITToggleStyle.swift`,
   `HITChip.swift`, `HITField.swift`, `HITSheetChrome.swift`, `HITSegmented.swift`, `HITMenuRow.swift`):
   - Spacing scale (4/8/12/16/24), radii (6 chips, 10 fields, 14 cards, 999 pills), type roles
     (title, body, caption, mono for queries) on top of `Theme`.
   - `HITButtonStyle`: `.primary` (accent fill, near-black text, pill, 34pt tall, pressed = 8% darker,
     disabled = 35% opacity), `.secondary` (1pt `Theme.separator` outline, label `Theme.secondaryText`),
     `.ghost` (text only, for Cancel), `.destructive` (P1 red outline, fills on hover/press). Hover states
     on macOS, 150 ms eased transitions, Reduce Motion respected. No default `.bordered`/`.borderedProminent`
     anywhere in the files you own when you are done.
   - `HITToggleStyle`: 42×24 track, off `#303948`, on accent, 20pt thumb with a 1pt inner highlight and
     soft shadow, thumb slides with a spring; label on the left, toggle right, works with `Toggle(isOn:)`.
   - `HITChip`: Todoist-style pill (icon + text, optional tint, optional dismiss ×), `.selected`
     state; a `HITChipRow` that wraps.
   - `HITField`: single and multi-line text input on `Theme.elevated`, 10pt radius, accent focus ring,
     placeholder in `Theme.secondaryText`, optional leading icon and trailing clear button.
   - `HITSheetChrome`: the frame every editor uses: title (semibold 17), Cancel (ghost, left) and the
     primary action (right), 16pt insets, `Theme.surface` background, keyboard shortcuts ⎋ / ⌘↩.
   - `HITSegmented`: pill segmented control for 2-4 options (used for P1-P4 and for date presets).
   - `HITMenuRow`: a settings/list row with icon, title, optional value, chevron or trailing control.
   Everything previews in a `DesignSystemGallery` SwiftUI preview and is covered by a snapshot-free test
   that at least instantiates each style (compile-level safety) plus unit tests for any state logic.
2. **Editors.** Rebuild `FilterEditorView`, `ProjectEditorView` and `LabelEditorView` on the chrome:
   no default Form toggles or pickers. The filter editor keeps every feature from the last session
   (live count, English description, error underline, suggestion chips, Syntax help, templates) but the
   templates become `HITChip`s, the colour picker becomes a row of 8 colour dots, and Save/Cancel are the
   chrome's buttons. Project and label editors: name field, colour dots, Save.
3. **Settings + sidebar + toolbar.**
   - `SettingsView` and `DelightSettingsSection`: `HITMenuRow`s and `HITToggleStyle`; the sound picker
     becomes a row that opens a compact list with ▶ previews; keep every existing control and behaviour
     (iCloud status, reset, backups, reminders, sounds, haptics).
   - Sidebar section headers: the "+" sits 6pt after the section title, 13pt semibold, `Theme.secondaryText`,
     accent on hover/press; on macOS it fades in on hover of the header row; never at the trailing edge.
     Counts stay right-aligned. Check it on iPhone (simulator screenshot) and describe how it looks on Mac.
   - The "Show completed" eye: move out of the big toolbar button into a small `…` toolbar menu with a
     checkmark item "Show completed", and on macOS also ⌘⇧C. Same menu gets "Sort" placeholders disabled.
4. **Sweep + docs.** `grep` the files you own for `.buttonStyle(.bordered`, `.borderedProminent`,
   `Toggle(` without `HITToggleStyle`, `Picker(` with default style; replace all. Write
   `HITList/Support/DesignSystem/README.md` (one page: when to use which component, with code snippets)
   because the popouts session will read it. Add a "Design system" row under UI in ROADMAP.md marked done.

## Verify
Signed iPhone 17 simulator and Mac builds; open every editor and Settings and take simulator screenshots
(mention paths). `scripts/test.sh` green. Report per COMMON.md, including the component list and any
place you had to keep a system control and why.
