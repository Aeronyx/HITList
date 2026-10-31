# Brief 18: Quick-add card v2, reminder offsets, and the "+" options (deadline, location)

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first (especially "Where things stand" and
"Round 3 ownership"), then `HITList/Support/DesignSystem/README.md` (Popouts section) and the files
under `HITList/Views/Popouts/`. Build only on the design system.

## Why (George, 2026-10-31, after using build 4 on the iPhone)
"The task popout should be a clean, detached ovular element above the keyboard with lots of space; dim the
screen behind it, simply say 'Task Name' as a placeholder, and have easy buttons just below the task name
entry for '+' (a quick-add button that allows adding descriptions, labels, locations, deadlines, etc.), the
Date (auto-set to Today if the popout was opened while on the Today page), Priority, Reminders, and
Group, with a slim horizontally scrolling bar to access all those options. The user can set all of those
by just typing, for example 'Haircut tom 11am p1 !15mb' to set a Priority 1 haircut task for tomorrow at
11am with a reminder 15 minutes beforehand. The font should be 14pt and bold when naming a task."

## Files you own
Everything under `HITList/Views/Popouts/` except `QuickAddEntry.swift` (the tabs session owns the floating
"+" and the tab chrome; you may change nothing there); `HITListCore/Sources/HITListCore/QuickAddParser.swift`
and `DateExpression.swift` (+ their tests in `HITListCore/Tests`); `HITList/Services/NotificationScheduler.swift`
and `HITList/Services/Notifications/*`; `HITList/Services/TaskActions.swift` (`create(from:)` only);
`HITListTests/PopoutTests.swift`, `HITListTests/Notification*Tests.swift`; the Popouts section of the
DesignSystem README; ROADMAP row named below. Do not touch `HITTokens.swift`, `Models.swift`,
`SchemaVersions.swift`, `TaskRow.swift`, `TaskListView.swift`, `ContentView.swift`, anything under
`Flipboard/`, `Inbox/`, `Upcoming/`.

## Know before you start
- Schema V2 (on master) already has the fields you need on `TaskItem`: `reminderOffsetMinutes: Int?`
  (nil = remind at the due time), `deadline: Date?`, `locationName: String?`. Do not add fields.
- `HITType.taskName` is Inter 14 bold and `TokenHighlightField` already uses it. `HITColor.due(...)`
  gives the date colours; `PopoutTint` wraps them.
- The card is `QuickAddPopout` (text ↔ chips through the pure `QuickAddDraft`), hosted by `PopoutHost`
  (`floatingQuickAdd`), opened by `PopoutController.openQuickAdd(context)`. `QuickAddContext` sets the
  defaults (`.today` → today, `.project(name:)` → that Group). The tabs session's "+" calls
  `popouts.openQuickAdd()` with `popouts.listContext`, so the Today default already works once the card is
  opened from the Today tab.
- "Group" is the user-facing word for Project from this round on (the chip reads "Group", "Inbox" when none).
- `DateExpressionParser` already accepts "tom"/"tmr"/"tmrw".
- Reminders fire at the due time today (`NotificationScheduler` builds `UNCalendarNotificationTrigger`s
  from `dueDate`); the plan lives in `Services/Notifications/`.

## Task, in commits
1. **Parser: reminder offsets.** New token kind `.reminder`: `!15mb`, `!1hb`, `!2hb`, `!1db` (minutes/
   hours/days before; the trailing `b` optional, `!15m` means the same), `!0` or `!at` = at the time.
   `QuickAddResult.reminderOffsetMinutes: Int?`; tinted like time tokens. `TaskActions.create` stores it
   and the new `deadline`/`locationName` when the result carries them (see 4). Tests in HITListCore.
2. **Notifications honour the offset.** The trigger is `dueDate − offset` (never in the past: if the
   offset time has passed but the due time hasn't, fire now; if both passed, the existing late-grace rule).
   Copy says "in 15 min · Haircut" style when offset > 0. Tests on the plan builder.
3. **The card, redesigned (iPhone first, Mac panel follows).** A detached oval: `RoundedRectangle` radius
   ≈ 28, inset 12 pt from the screen edges, floating 12 pt above the keyboard (not docked), slate
   `Theme.surface`, hairline border, generous padding (20 pt), dim backdrop (black 0.5) that closes on tap.
   Placeholder "Task Name"; the title in `HITType.taskName`. Directly under the field, one slim
   horizontally scrolling bar (`ScrollView(.horizontal)`, 30 pt tall chips, `HITChip` with a compact
   size if you add one to the design system file `HITChip.swift` — that file you may edit for this only):
   in order **"+"**, **Date** (reads "Today" in green when opened from Today, "Date" otherwise), **Priority**,
   **Reminder**, **Group** (reads the Group name or "Inbox"), then **Labels**, **Repeat** when set. The "+"
   opens a popover menu: Description, Labels, Location, Deadline, Repeat; picking one reveals that
   control inside the card (Description line, label picker, a Location text field, a Deadline date
   popover with "Deadline" chip appearing in the bar). The autocomplete row appears only while there are
   suggestions. Return saves and keeps the card open and empty; the "Added ‘…’" note stays. Mac: the same
   contents in the existing 560 pt panel.
4. **Chips in both directions.** Reminder chip popover: offset presets (At time, 5 min, 15 min, 30 min,
   1 hour, 1 day before) above the existing time-of-day presets; picking writes `!15mb` into the text and
   the chip reads "11:00 AM · 15 min before". Deadline and Location have no text token: they live in
   `QuickAddDraft` as plain values and in `QuickAddResult`. `TaskPopout` gets the same Reminder offset
   UI and shows Deadline and Location chips when set (editable), plus Location/Deadline in its `…` menu.
5. **Tests and docs.** `PopoutTests`: `!15mb` ↔ chip round trip, offset presets write the right token,
   deadline/location survive save, Today default still today-without-time. README Popouts section
   updated with the oval card, the "+" menu, and the reminder grammar. ROADMAP: row "Quick-add v2 (oval
   card, '+' options, reminder offsets, deadline, location)" under UI, marked done.

## Verify
Signed iPhone 17 simulator build. Record a video: open the card, type "Haircut tom 11am p1 !15mb", watch
Tomorrow / P1 / 11:00 AM · 15 min before fill in, save, open the task, add a location and a deadline from
"+", change the reminder offset from its chip. A unit test shows the notification trigger at 10:45.
Mac build and tests green (`scripts/test.sh`). Report per COMMON.md.
