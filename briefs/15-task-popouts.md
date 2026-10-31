# Brief: Task popouts, Todoist-style (no right sidebar)

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md`, then `HITList/Support/DesignSystem/README.md`
(from the merged design-system session; build only on those components).

## Why
George: Todoist has no right sidebar and HITList shouldn't either. Tasks should pop out at the bottom
middle on iPhone and top-ish middle on Mac, with a simple interface that only gets more complex when you
press buttons. Today ⌘N / New Task only focuses an inline field, with no visible feedback. There is no
easy way to add a description, labels, etc. Most of the time George adds tasks from the popout on the
phone or directly inside an existing list on the laptop (Todoist's inline add row).

## Files you own
`HITList/Views/ContentView.swift`, `HITList/Views/TaskListView.swift`, `HITList/Views/TaskRow.swift`,
`HITList/Views/QuickAddBar.swift` (replace), `HITList/Views/TaskDetailView.swift` (replace), new
`HITList/Views/Popouts/`, `HITList/HITListApp.swift` (the New Task command and ⌘N only), one line each in
`UpcomingView.swift`, `FlipboardView.swift` and `InboxView` where they open a task or quick-add, so they
use the popouts. New tests in `HITListTests/`.

## Know before you start
- `HITList/Views/Inbox/InboxView.swift` has its own list implementation (it does not wrap `TaskListView`), as
  does `HITList/Views/Upcoming/UpcomingView.swift`. Your quick-add popout, floating "+", inline add row and task
  popout must work in all three: TaskListView, InboxView, UpcomingView. Prefer one shared presenter
  (an `@Observable` popout controller injected via the environment) over per-view copies.
- The Flipboard (`HITList/Views/Flipboard/`) opens a task via "Open task"; route that through the task popout too.
- Design-system components are documented in `HITList/Support/DesignSystem/README.md` and shown in the
  `DesignSystemGallery` preview. No default `.bordered`/`.borderedProminent` buttons, plain `Toggle`s or
  default pickers anywhere you touch.

## Task, four commits
1. **Two columns, not three.** `NavigationSplitView` becomes sidebar + list on Mac/iPad; iPhone stacks.
   Remove the detail column and `selectedTask` plumbing; selection now means "present the task popout".
2. **Quick-add popout.** One component `QuickAddPopout` used everywhere:
   - iPhone: a card docked to the bottom above the keyboard (the keyboard-attached style in Todoist),
     slate `Theme.surface`, 14pt radius top corners. Triggered by a floating accent "+" button bottom-right
     in every list (hide while the popout is up).
   - Mac: a floating panel 560pt wide centred horizontally about 18% from the top of the window, dimmed
     backdrop, opened by ⌘N, the toolbar "+", and the inline "Add task" row at the end of every list
     (Todoist style: the row expands into the same card in place).
   - Contents: `HITField` for the title with live token highlighting from `QuickAddParser` (dates,
     `#project`, `@label`, `p1-p4` tinted), a second optional description line that appears after tapping
     "Description", then one `HITChipRow`: Date (default: the list's context, e.g. Today in Today),
     Priority, Reminder, Project (default Inbox or the current project), Labels; each chip opens a compact
     popover (date presets + calendar; P1-P4 segmented; project list with search). Typing natural language
     updates the chips live, and tapping a chip writes the token back into the text, exactly like Todoist.
     Autocomplete from `AutocompleteEngine` appears as a thin suggestion row above the chips. ↩ saves and
     keeps the popout open with an empty field for the next task; ⎋ / × closes; the submit button is a
     primary `HITButtonStyle` circle with an arrow.
3. **Task popout.** `TaskPopout` replaces `TaskDetailView`: bottom sheet on iPhone (`.presentationDetents`
   medium/large, slate background, grabber), the same top-centred panel on Mac. Minimal by default:
   checkbox + title (editable inline), description (collapsed "Add description" until tapped), the same
   chip row (date, priority, project, labels, reminder, repeat), an "Add to Flipboard" row when the task
   repeats. A `…` menu holds Duplicate, Move, Delete. Completing from the popout uses the existing
   completion feedback and closes with the toast. Tapping a row anywhere opens it; swipe actions stay.
4. **Tests + docs.** Pure tests: parsed-text ↔ chip state round trip (every token kind), default date and
   project per list context, popout presentation state (open/close/keep-open-after-save), and that
   saving from Today sets today's date without a time. Update the DesignSystem README with the two
   popouts. ROADMAP: "Task popouts" row under UI marked done.

## Verify
Signed iPhone 17 simulator and Mac builds. Record a simulator video: open quick-add from the "+", type
"Call mom tomorrow 5pm #Family @calls p2", watch the chips fill, save, open the task, add a description,
change the date via the chip, complete it. Mention the path. `scripts/test.sh` green. Report per COMMON.md.
