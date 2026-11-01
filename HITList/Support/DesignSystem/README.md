# HITList design system

HITList draws its own controls. Never use `.bordered`, `.borderedProminent`, a default `Toggle`,
a segmented `Picker`, or a `Form` in new UI; use the components below. Colours come from `Theme`
(slate + `#6C9EFF` accent) and `Priority.color`; numbers come from `HITTokens.swift`. Every component
is in `DesignSystemGallery` (open it in the Xcode canvas) and rendered by `DesignSystemTests`.

## Tokens (`HITTokens.swift`)
`HITSpacing.xs/s/m/l/xl` = 4/8/12/16/24. `HITRadius.chip/field/card/pill` = 6/10/14/999.
Type is **Inter** everywhere (`HITFont.inter(size, weight, relativeTo:)`; six static 18 pt cuts ship in the
bundle and `UIAppFonts`/`ATSApplicationFontsPath` register them). Use the `HITType` roles, never
`.font(.subheadline)`: `.largeTitle`, `.title1/2/3` (+ `.title2Bold`), `.headline`, `.body`, `.callout`
(+ `Medium`/`Bold`), `.subheadline` (+ `Medium`/`Semibold`), `.footnote`, `.caption` (+ `Bold`),
`.caption2` (+ `Semibold`), `.control` (button/chip labels), `.title` (sheet titles, fixed 17 semibold),
`.taskName` (quick-add title, bold, one step above body: 20 on iOS, 15 on Mac), `.sectionHeader`, `.mono`/`.monoCaption` (system mono for
queries). SF Symbols keep `.font(.system(size:weight:))`. The window root sets `.font(HITType.body)`, so
unstyled `Text` is Inter. `HITColor.onAccent` (near-black text on accent), `.text`, `.danger` (P1 red),
and the due colours `.dueToday` (green) / `.dueTomorrow` (orange) / `.dueLater` (purple) /
`.dueOverdue` (red) with `HITColor.due(date, hasTime:now:)` choosing among them.
`HITMotion.standard(reduceMotion:)` (150 ms ease) and `.spring(reduceMotion:)`; pass
`@Environment(\.accessibilityReduceMotion)`. `Color.darkened(by:)` for pressed fills.

## Which component
| Need | Use |
|---|---|
| The one main action on a screen (Save, Add, the quick-add submit) | `.buttonStyle(.hitPrimary)`; circle: `HITButtonStyle(.primary, shape: .circle)` |
| Any other visible button | `.hitSecondary` |
| Cancel, Done, quiet inline actions | `.hitGhost` |
| Delete / Remove / Reset | `.hitDestructive` (red outline, fills on hover/press) |
| A bare icon (toolbar, row accessory, sidebar "+") | `.hitIcon` / `HITIconButtonStyle(font:alignment:)` |
| Smaller buttons in rows | `HITButtonStyle(.secondary, size: .small)` (28 pt; regular is 34) |
| On/off | `Toggle(...).toggleStyle(.hit)` |
| Date, priority, project, label, reminder tokens | `HITChip`, several in `HITChipRow` (wraps) |
| A chip as a `Menu` label | `HITChipLabel` |
| Text input | `HITField` (single or `axis: .vertical`); a `TextField` you can't replace: `.textFieldStyle(HITTextFieldStyle())` |
| 2-4 exclusive options (P1-P4, date presets) | `HITSegmented` + `HITSegment` |
| Colour choice | `HITColorDots(selection: $hex)` |
| An editor sheet | `HITSheetChrome` with `HITSection`s inside |
| Settings-style lists | `HITGroup` of `HITMenuRow`s |

All of them: hover state on macOS, 35% opacity when `.disabled`, Reduce Motion respected.

## Snippets
```swift
// Buttons
Button("Save", action: save).buttonStyle(.hitPrimary)
Button("Cancel") { dismiss() }.buttonStyle(.hitGhost)
Button { submit() } label: { Image(systemName: "arrow.up") }
    .buttonStyle(HITButtonStyle(.primary, shape: .circle))
    .disabled(title.isEmpty)

// Toggle: label left, 42x24 switch right; the whole row toggles.
Toggle("Haptics", isOn: $haptics).toggleStyle(.hit)

// Chips: tint colours the icon; selected fills with the tint. onDismiss adds an x.
HITChipRow {
    HITChip("Today", systemImage: "calendar", tint: .green, isSelected: hasDate) { showDate = true }
        .popover(isPresented: $showDate) { DatePopover() }
    HITChip("P2", systemImage: "flag.fill", tint: Priority.p2.color, isSelected: true) { showPriority = true }
    HITChip("@calls", systemImage: "tag", onDismiss: { remove(label) }) { }
}
Menu { projectButtons } label: { HITChipLabel("Inbox", systemImage: "tray") }
    .menuStyle(.button).buttonStyle(.plain).fixedSize()

// Fields: elevated box, accent focus ring, red ring when invalid. .onSubmit etc. pass through.
HITField("Task name", text: $title, autofocus: true).onSubmit(save)
HITField("Description", text: $notes, axis: .vertical, lineLimit: 1...6)
HITField("Search projects", text: $search, systemImage: "magnifyingglass", clearable: true)

// Segmented
HITSegmented(selection: $priority, segments: Priority.allCases.map {
    HITSegment($0, "P\($0.rawValue)", systemImage: $0.symbol, tint: $0.color)
})

// Editor sheet: ghost Cancel left, title centred, primary right; Esc cancels, Cmd-Return saves.
// No NavigationStack; present with .sheet { … .slateSheet() }.
HITSheetChrome("New Project", isPrimaryEnabled: !name.isEmpty, onPrimary: save) {
    HITSection("Name") { HITField("Name", text: $name, autofocus: true).onSubmit(save) }
    HITSection("Colour") { HITColorDots(selection: $colorHex) }
}
// cancelTitle: nil gives a Done-only sheet; background: Theme.background for a page of groups.

// Settings-style rows
HITGroup("Reminders", footer: "Only tasks with a time get a notification.") {
    HITMenuRow("Sound", systemImage: "speaker.wave.2", value: "Bubble") { open() }        // chevron
    HITMenuRow("Details", accessory: .expand(isExpanded: open)) { open.toggle() }        // turns down
    HITMenuRow("Back up now", systemImage: "externaldrive", accessory: .none) { backUp() }
    HITMenuRow("Reset…", systemImage: "arrow.counterclockwise", role: .destructive, accessory: .none) { reset() }
    HITMenuRow("Account", value: "Available")                                           // read-only
    HITMenuRow("Custom", systemImage: "waveform") { Button("Remove") { }.buttonStyle(HITButtonStyle(.destructive, size: .small)) }
    Toggle(isOn: $on) { HITMenuRowLabel("Notify", subtitle: "…", systemImage: "bell") }
        .toggleStyle(.hit).hitRowPadding()   // any other content in a group: .hitRowPadding()
}
```

## Popouts (`HITList/Views/Popouts/`)
There is no detail column: tasks are added and opened in two popouts, presented by the one
`PopoutController` that `ContentView` puts in the environment and draws with `PopoutHost`.

| Popout | iPhone | Mac (and iPad) |
|---|---|---|
| `QuickAddPopout` (new task) | detached oval (`ovalCardChrome()`: 28 pt continuous corners, slate `Theme.surface`, hairline border, shadow) inset 12 pt from the screen edges, floating 12 pt above the keyboard over a black 0.5 backdrop that closes on tap; 20 pt padding; opened by the oval accent "+" above the tab bar's right end (`MobileShell`; iPad keeps the floating "+") | the same contents in the 560 pt panel centred ~18% from the top over a dimmed backdrop; opened by ⌘N and the toolbar "+" |
| Inline add (same card, in place) | the "Add task" row opens the oval card | the "Add task" row at the end of a list expands into the card |
| `TaskPopout` (open a task) | bottom sheet, medium/large detents, grabber | the same top-centred panel |

```swift
// A list that tasks can be added into: ⌘N context, floating "+" (iOS) or toolbar "+" (Mac).
content.quickAddEntry(.project(name: project.name))
// The last row of the list.
Section { InlineAddRow(context: .today, key: "list") }
// Opening a task: select its row in a List(selection: popouts.selection), or
popouts.open(task)
```
- `QuickAddContext` sets the defaults: Today/Upcoming = today without a time, an Upcoming day = that
  day, a project = that project, a label = that label, Inbox = undated in the Inbox.
- The quick-add card, top to bottom: the title (placeholder "Task Name", `HITType.taskName`, Inter 20
  bold, `TokenHighlightField(bordered: false)` since the card is the frame), any revealed Description /
  Location fields, the autocomplete row (only while it has suggestions), then one slim horizontally
  scrolling bar of `HITChip(size: .compact)` chips (30 pt capsules; an untitled chip is a 30 pt icon
  circle): **"+"**, **Date** ("Today" in green from Today, "Date" elsewhere), **Priority**, **Reminder**
  ("11:00 AM · 15 min before"), **Group** (its name, or "Inbox"), then **Labels**, **Deadline**,
  **Repeat** once set or picked from "+". Last, the "Added ‘…’" note, × and the send button.
- **"+"** is a menu: Description, Labels, Location, Deadline, Repeat. Picking one reveals it in the card
  (`QuickAddDraft.reveal`): Description and Location are fields that take the cursor; Labels, Deadline and
  Repeat add their chip to the bar and open its popover. Deadline and Location have no text token; they
  live in `QuickAddDraft` (`deadline`, `locationName`) and reach `QuickAddResult` and `TaskActions.create`.
- `QuickAddDraft` keeps the text and the chips in step (typing fills chips; picking a chip writes its
  token: `tomorrow`, `5:30pm`, `p2`, `#"Two Words"`, `@label`, `every weekday`, `!15mb`). Pure; see
  `PopoutTests`. Example: "Haircut tom 11am p1 !15mb" = Tomorrow · P1 · 11:00 AM · 15 min before.
- **Reminder grammar** (`ReminderOffset` in HITListCore): `!15mb` or `!15m` = 15 minutes before the due
  time, `!1hb`/`!1h` = 1 hour, `!1db`/`!1d` = 1 day (up to 4 weeks); `!0` or `!at` = at the time (no
  offset). Only the first one counts; it tints like a time. The Reminder popover's offset presets (At
  time, 5 min, 15 min, 30 min, 1 hour, 1 day before) write the token and stay open so a time can follow;
  the time presets below them close it. Stored as `TaskItem.reminderOffsetMinutes` (nil = at the time);
  the notification goes out at due − offset reading "in 15 min · Haircut" (`NotificationPlan`).
- Chip popovers live in `PopoutPickers.swift` (date, deadline via `DateChipPopover(title:clearTitle:)`,
  priority, reminder, group, labels, repeat, location) and are shared by both popouts. `TaskPopout` has
  the same Reminder offset UI, shows Deadline and Location chips when set (tap to edit, × to remove),
  and offers Location / Deadline in its `…` menu.
- Return saves and keeps the card open and empty; Esc, × or a tap on the backdrop closes. Completing in
  `TaskPopout` plays the usual completion feedback, closes it, and shows the undo toast.

## Notes for builders
- `HITMenuRow("Title") { … }` with a statement closure is a tappable row; a closure that returns a
  view is the trailing control. Keep action closures non-empty.
- `HITGroup` puts hairlines between its direct children, including `if` and `ForEach` rows.
- System controls kept on purpose: `Menu` bodies, `confirmationDialog`, `alert`, file importer and
  exporter, navigation/toolbars, and `List` (swipe actions, selection, reordering). Style their
  labels, not their chrome.
