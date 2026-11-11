# HITList design system

HITList draws its own controls. Never use `.bordered`, `.borderedProminent`, a default `Toggle`,
a segmented `Picker`, or a `Form` in new UI; use the components below. Colours come from `Theme`
(the current dark palette; see Themes below) and `Priority.color`; numbers come from `HITTokens.swift`. Every component
is in `DesignSystemGallery` (open it in the Xcode canvas) and rendered by `DesignSystemTests`.

## Tokens (`HITTokens.swift`)
`HITSpacing.xs/s/m/l/xl` = 4/8/12/16/24. `HITRadius.chip/field/card/pill` = 6/10/14/999.
Type is **Inter** everywhere (`HITFont.inter(size, weight, relativeTo:)`; six static 18 pt cuts ship in the
bundle and `UIAppFonts`/`ATSApplicationFontsPath` register them). Use the `HITType` roles, never
`.font(.subheadline)`: `.largeTitle`, `.title1/2/3` (+ `.title2Bold`), `.headline`, `.body`, `.callout`
(+ `Medium`/`Bold`), `.subheadline` (+ `Medium`/`Semibold`), `.footnote`, `.caption` (+ `Bold`),
`.caption2` (+ `Semibold`), `.control` (button/chip labels), `.title` (sheet titles, fixed 17 semibold),
`.taskName` (quick-add title, bold, one step above body: 19 on iOS, 15 on Mac), `.taskTitle`/`.taskMeta` (a task
row's title, with `.taskTitleTracking`, and its second line), `.sectionHeader`, `.listSectionHeader` (task-list headers, applied by `taskSectionHeader`; rows and headers measure from `ListMetrics`), `.mono`/`.monoCaption` (system mono for
queries). SF Symbols keep `.font(.system(size:weight:))`. The window root sets `.font(HITType.body)`, so
unstyled `Text` is Inter. The Mac draws text without font smoothing (`HITFont.smoothsMacText`, set at launch by
`installPlatformAppearance`), as the iPhone always has.

| Task lists (round 15, brief 67) | Mac | iPhone |
|---|---|---|
| Row title (`taskTitle`) | Inter 14 regular, tracking 0 | Inter 17 regular, tracking −0.3 |
| Second line (`taskMeta`) | Inter 12 regular | Inter 13 regular |
| Section header (`listSectionHeader`) | Inter 14 bold | Inter 16 semibold |
| Title baseline to second line's | 22 pt (`rowLineGap` 5.5) | 20.9 pt (`rowLineGap` 4) |

The Mac row matches George's target (Todoist's Mac row, SF Pro 14 over 12 drawn without smoothing) in width and
weight; the iPhone row is the size the Duo's outer display used since brief 63, now every iPhone's.

`HITColor.onAccent` (near-black text on accent), `.text`, `.danger` (P1 red),
and the due colours `.dueToday` (green) / `.dueTomorrow` (orange) / `.dueLater` (purple) /
`.dueOverdue` (red) with `HITColor.due(date, hasTime:now:)` choosing among them.
`Color.darkened(by:)` for pressed fills.

## Motion (`HITMotion`)
Six roles; pick by what is happening. Nothing outside `celebrate` bounces or takes over 250 ms to arrive.

| Role | Curve | Use for |
|---|---|---|
| `quick` | 100 ms ease-out | hover highlights, press feedback |
| `standard` | 150 ms ease-in-out | state changes: selection, focus ring, enabled, a row expanding |
| `enter` | 200 ms ease-out | something appearing: toast, popout, revealed field |
| `exit` | 150 ms ease-in | something leaving: a completed row sliding away, a toast expiring |
| `emphasis` | spring, response 0.28, damping 0.8 (arrives in ~233 ms, 1.5% overshoot) | moving parts: toggle thumb, segment highlight |
| `celebrate` | scale to 1.2 in 90 ms, spring settle (0.3 / 0.62) | the completion check, nothing else |
| `tabPill` | spring, response 0.28, damping 0.86 (no visible bounce; the pill stretches 10% mid-way) | the island's pill sliding to the tapped tab, and the tab's icon and label with it |
| `tabSwitch` | 200 ms ease-in-out (150 ms plain fade with Reduce Motion) | the crossfade between tab screens, the new one rising 6 pt |

Each has a `(reduceMotion:)` variant (`HITMotion.emphasis(reduceMotion:)`): `quick`/`standard` become instant,
`enter`/`exit`/`emphasis` a 100 ms ease, `celebrate` nil. Pass `@Environment(\.accessibilityReduceMotion)`, or
read `@HITEffectsSetting private var effects` and use `effects.animation(.emphasis)`, which also calms the
larger movements when the app's Reduce Effects switch is on. `HITMotion.spring` is the deprecated old name of
`emphasis`.

```swift
.animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
.animation(effects.animation(.emphasis), value: isOn)
withAnimation(effects.animation(.enter)) { showToast = true }
```

Built on the roles (round 17, brief 75; each measured frame by frame on the simulator and the Mac):
- **With the keyboard** (iPhone cards): `KeyboardObserver.height` moves on `KeyboardObserver.Follow`, the keyboard's
  own curve (an ease-out, `1 - e^(-t/τ)`, τ a fifth of the notification's duration), set on the next turn of the run
  loop: a SwiftUI change made inside UIKit's keyboard animation is drawn wrongly. Never animate with the keyboard
  any other way.
- **Panels** (Mac and iPad quick add, editor, shared task): `PanelBackdrop.transition` fades the backdrop and panel
  as the panel comes down 6 pt into place, in on `enter`, back up and out on `exit`. (Not a scale: under one, the
  editor's scrolling row of pills came to rest scrolled 2.5 pt off.)
- **The Mac sidebar's selection**: `macSidebarSelectionGlide(selection)` on a column of `MacSidebarRow`s draws one
  fill that glides to the selected row on `tabPill`, as the iPhone island's pill does.
- **Numbers** that change in place roll (`.contentTransition(.numericText(value:))` on `standard`).

## Material (`HITMaterial.swift`)
`hitGlass(in:tint:interactive:fallback:)` is the one way to draw Liquid Glass: glass on iOS 26 / macOS 26 when
effects are allowed, the slate fill otherwise (`fallback`, else the tint, else `Theme.surface`). Glass is off
under Settings → Appearance → Reduce effects (`Preferences.reduceEffects`) and the system's Reduce
Transparency (`HITEffects.allowsGlass(osSupportsGlass:reduceEffects:reduceTransparency:)`, pure). Glass is a
highlight, not a wallpaper: bars, floating controls and moving highlights, never list rows or page backgrounds.

```swift
header.hitGlass(in: Rectangle())                                  // a bar
plus.hitGlass(in: Circle(), tint: Theme.accent, interactive: true) // a floating control
highlight.hitGlass(in: Capsule(), fallback: Theme.separator)      // keeps today's slate when glass is off
```

Where the components use glass (iOS 26 / macOS 26, effects allowed; build 5's slate look otherwise):
`HITSheetChrome`'s header bar (the content scrolls under it, `scrollEdgeEffectStyle(.soft, for: .top)`; this is
also the iPhone Settings sheet's bar), `HITSegmented`'s moving highlight, and the hover fill of an unselected
`HITChip`. Everything else stays slate.

## Themes (`Theme.swift`)
Four dark palettes (`ThemePalette.all`): **Slate** (default, build 5's colours), **Graphite** (neutral greys,
off-white `#E6E1D6` accent), **Midnight** (blue-black, cyan `#4FD1E8`), **Moss** (green-black, `#8FD694`). Each
has eight colours: `background`, `surface`, `elevated`, `separator`, `accent`, `secondaryText`, `text`,
`onAccent`. `Theme.background` etc. and `HITColor.text`/`.onAccent` read the current one from
`ThemeStore.shared` (`@Observable`, saved at `Preferences.theme`), so views redraw live when it changes. Never
cache a `Theme` colour in a `static let` or `@State`; read it in `body`. Due and priority colours are the same in
every theme. Every text/surface pair passes WCAG AA (`ThemeTests`).

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
| 2-4 exclusive options (P1-P4, date presets, a filter) | `HITSegmented` + `HITSegment`; `size: .small` (28 pt in all) beside small buttons |
| Colour choice | `HITColorDots(selection: $hex)` |
| A day (due date, deadline) | `HITCalendar` (never the system `DatePicker`) |
| An editor sheet | `HITSheetChrome` with `HITSection`s inside |
| A sheet whose pages open inside it (iPhone and iPad Settings) | `HITSheetPages`: the first screen under the bar, a page pushed in on `enter`/`exit` with "‹ back" in the bar, the edge swipe, Esc; never a second sheet |
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

// A sheet with pages (brief 86): any view inside opens one with @Environment(\.hitPages) var pages; pages(page).
HITSheetPages("Settings", path: $path, title: \.title, onPrimary: { dismiss() }) {
    HITGroup { HITMenuRow("General", systemImage: "gearshape") { path.append(.general) } }
} destination: { page in
    SettingsPageContent(page: page)
}

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

## Calendar (`HITCalendar.swift`)
A month grid in Inter, drawn by us instead of the system graphical `DatePicker`: "November 2026" in
`HITType.headline`, ‹ and › with a dot between them that returns to this month (accent while another month
shows), weekday initials in `Theme.secondaryText`, then always six weeks of 32 pt day circles so the height
never changes. Today is ringed in the accent; the selected day is filled with it and its number is
`HITColor.onAccent`; the neighbouring months' days are dimmed and past days a little dimmer; hover fills
`Theme.elevated` (`quick`). With keyboard focus, the arrow keys move the selection (crossing months) and
Return picks it; a click picks at once. Weeks start on the user's choice (`Preferences.weekStartWeekday()`).
The grid maths is pure and tested: `HITCalendar.weeks(for:month:weekStart:calendar:)`,
`weekdayInitials(weekStart:calendar:)`, `moved(_:_:calendar:)`.

```swift
HITCalendar(selection: due, today: now, weekStart: Preferences.weekStartWeekday(),
            focusTrigger: focusRequest) { day in onPick(day) }
```

## Popouts (`HITList/Views/Popouts/`)
There is no detail column: tasks are added and opened in two popouts, presented by the one
`PopoutController` that `ContentView` puts in the environment and draws with `PopoutHost`.

| Popout | iPhone | Mac (and iPad) |
|---|---|---|
| `QuickAddPopout` (new task) | detached oval (`ovalCardChrome()`: 28 pt continuous corners, slate `Theme.surface`, hairline border, shadow) inset 12 pt from the screen edges, floating 12 pt above the keyboard over a black 0.5 backdrop that closes on tap; 20 pt padding; opened by the oval accent "+" above the tab bar's right end (`MobileShell`; iPad keeps the floating "+") | the same contents in the 560 pt panel centred ~18% from the top over a dimmed backdrop; opened by ⌘N and the toolbar "+" |
| Inline add (same card, in place) | the "Add task" row opens the oval card | the "Add task" row at the end of a list expands into the card |
| `TaskPopout` (open a task) | bottom sheet, medium/large detents, grabber: a title card (check circle, title, Group row, date row), value pills (Description, Priority, Reminder, Labels, Repeat, Deadline, Location), the Sub-tasks checklist, and one Confirm pill that saves typing and closes (brief 32) | the same top-centred panel; ⌘Return confirms |

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
- The quick-add card, top to bottom: the title (placeholder "Task Name", `HITType.taskName`, Inter 19
  bold, `TokenHighlightField(bordered: false)` since the card is the frame), any revealed Description /
  Location fields, then one slim horizontally scrolling bar of `HITChip(size: .compact)` chips (30 pt capsules; an untitled chip is a 30 pt icon
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
- **Relative times** (`DateExpressionParser.matchRelativeTime`): "in 10 minutes", "in 10 min", "in two
  hours", "in an hour", "in half an hour" set the due time that far from now, to the minute; "in 3 days",
  "in a week", "in 2 weeks", "in a month" set the day (number words one to twelve, or digits), keeping a
  time typed beside them. One `.date` token. Minutes and hours need "in": "Run 10 minutes" is a title.
- **Reminder grammar** (HITListCore `ReminderPhrase`, `ReminderOffset`; brief 48, 0.7.0): `!15m`, `!2h`,
  `!1d`, `!1h30m` = a reminder that long **from now**, with or without a due date (`TaskItem.reminderDate`);
  `!15mb`, `!1hb`, `!1db` = that long **before** the due time, which needs a time ("tom 11am", "in 2 hours");
  `!0` or `!at` = at the due time. Nothing else is one (`!`, `!0mb`, `!m`, `!15` stay title text). A "!" phrase
  lights up and counts only once it is complete: followed by a space, or at Confirm. One from-now and one
  before-due reminder may stand together; a later one of the same kind overrides. It tints like a time. The Reminder card's offsets (At time, 5, 10,
  15, 30 min, 1 hour, 1 day before, two per row, and a custom "N min before" field) write the token and
  stay open so a time can follow; a time (typed or 9 AM / Noon / 5 PM / 8 PM) closes it. The card says
  when it fires ("Fires 10:45 AM"). Stored as `TaskItem.reminderOffsetMinutes` (nil = at the time);
  the notification goes out at due − offset reading "in 15 min · Haircut" (`NotificationPlan`).
- **Picker cards.** Each chip opens a card through `pickerAnchor(_ kind:isPresented:content:)`, and each
  popout's root has one `pickerOverlay()` (`Views/Popouts/Pickers/PickerPresenter.swift`). On the Mac the
  card is drawn inside the window, never as an `NSPopover`: below its chip, above it when there is no
  room, slid inside when neither fits, and clamped so it never leaves the window
  (`PickerPlacement.frame(anchor:cardSize:bounds:)`, tested). It is `Theme.surface` (glass when effects
  are allowed) with a hairline border, 14 pt corners and a soft shadow, in and out with `enter`/`exit`.
  Escape and a click outside close only the card (not the popout); picking closes it; Tab moves the
  keyboard into it and closing gives it back to the title. Because the popout panel clips what it draws,
  the card lives on one transparent layer over the window's content (`PickerLayerHost`) and a local event
  monitor handles Escape, Tab and clicks while a card is open. iPhone and iPad keep SwiftUI popovers.
- The cards: `DatePickerCard` (presets Today, Tomorrow, Next week, Weekend, No date; `HITCalendar`; the time
  row, a `HITField`-styled box that takes "9am", "17:30", "noon" via `PickerTime.parse`; the Repeat chip;
  Deadline uses it with `title: "Deadline"`, no time or repeat), `ReminderPickerCard`, and in
  `PopoutPickers.swift` priority, group, labels, repeat and location. They are shared by both popouts.
  `TaskPopout` shows Deadline and Location chips when set (tap to edit, × to remove) and offers Location /
  Deadline in its `…` menu.
- Return saves and keeps the card open and empty; Esc, × or a tap on the backdrop closes. Completing in
  `TaskPopout` plays the usual completion feedback, closes it, and shows the undo toast.

## Notes for builders
- `HITMenuRow("Title") { … }` with a statement closure is a tappable row; a closure that returns a
  view is the trailing control. Keep action closures non-empty.
- `HITGroup` puts hairlines between its direct children, including `if` and `ForEach` rows.
- System controls kept on purpose: `Menu` bodies, `confirmationDialog`, `alert`, file importer and
  exporter, navigation/toolbars, and `List` (swipe actions, selection, reordering). Style their
  labels, not their chrome.
