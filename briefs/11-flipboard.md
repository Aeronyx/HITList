# Brief: Task Flipboard

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first.

## The dream, in George's words
A physical wall board of switches and lights: each recurring self-care task or chore ("Shave") is a
switch that flips from the green side to the red side after its interval (every 3 days) and resets
when you flip it back. The digital version has to feel satisfying, not like checkmark buttons.

## Files you own
New files under `HITList/Views/Flipboard/`, new test files in `HITListTests/`. One-line insertions
only: a `case flipboard` in `SidebarItem` (`HITList/Views/ContentView.swift`) plus the routing line to
`FlipboardView`; one sidebar row in `HITList/Views/SidebarView.swift` next to Today/Upcoming (one
`Label("Flipboard", systemImage: "switch.2")` line in the existing smart-list section; nothing else
in that file); an "Add to Flipboard / Remove from Flipboard" toggle in `HITList/Views/TaskDetailView.swift`
(one small section). Do not edit `TaskListView.swift`, `TaskRow.swift`, `SettingsView.swift`, any
model, or `project.yml`.

## Model: no schema change
A Flipboard switch IS an existing recurring task: `recurrence` set (interval rules like "every 3 days"
work best; weekly rules work too), `hasDueTime == false`, and the label `flipboard` attached (create
it on demand through `TaskActions.findOrCreateLabel(named: "flipboard")`, and give it the stable id
`SeedIdentity.uuid(for: "TaskLabel/flipboard")` the first time). Green side = due date is in the
future; red side = due today or overdue; flipping back = `TaskActions.toggleCompletion`, which already
rolls the due date forward by the recurrence. The "light bar" is time elapsed in the interval
(`dueDate - interval` → `dueDate`). Interval length comes from `RecurrenceRule`; expose a helper in
your own files if the rule type lacks one.

## Task, three commits
1. **FlipboardView.** A wall: a responsive grid (2 columns on iPhone, 3-5 on Mac/iPad) of switch
   tiles on `Theme.surface`. Each tile: the task title in small caps, a large skeuomorphic rocker
   switch (rounded rectangle with a bevelled thumb, green face `#3DDC84`-ish dimmed to the slate
   palette vs red face `Priority p1` red), an LED dot that glows red when flipped, and a thin
   horizontal light bar filling as the interval elapses, with "2 of 3 days" under it. Overdue tiles
   pulse the LED slowly (no pulse under Reduce Motion). Sort: red first (most overdue at top), then
   green by soonest. Empty state explains how to add switches (from a task's detail view, or the "+"
   on the board which creates a task via a small sheet: title, every N days/weeks).
2. **The flip.** Tapping the rocker animates a real flip (3D rotation on the X axis with perspective,
   ~350 ms spring, thumb travels, LED goes out, light bar resets) and calls `toggleCompletion`.
   Haptic `.rigid` on iOS, `NSHapticFeedbackManager .alignment` on Mac. NO sound (George is picking
   their own completion sound separately). Flipping a green switch (early) asks "Mark 'Shave' done
   early?" with a confirm, then does the same. Long-press / right-click: Edit interval, Remove from
   Flipboard, Open task. The whole thing must feel physical: slight overshoot, shadow under the thumb.
3. **Tests + ROADMAP.** Pure helpers tested: membership rule, side (green/red) from dates, elapsed
   fraction (clamped), sort order, interval extraction for daily/every-N/weekly rules, and that a flip
   on an overdue task lands the next due date in the future. Add a "Task Flipboard" row under a "UI"
   heading in ROADMAP.md's status table marked done, and move the Flipboard idea out of the ideas
   backlog into a one-paragraph description of what shipped.

## Verify
Signed simulator and Mac builds: create "Shave every 3 days" and "Water plants every week", add them
to the Flipboard, back-date one so it's red, flip it, confirm the due date moved and the tile turned
green. Record a short simulator video (`xcrun simctl io booted recordVideo`), mention its path. Report
per COMMON.md.
