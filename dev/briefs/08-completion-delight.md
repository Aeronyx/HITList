# Brief: Completion delight (ROADMAP ideas backlog, first item)

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first.

## Goal
Completing a task should feel as good as it does in Todoist: a crisp sound, a satisfying check
animation, the title striking through, the row sliding away, and an easy undo. Dark slate aesthetic;
nothing cartoonish.

## Files you own
`HITList/Views/TaskRow.swift`, `HITList/Views/TaskListView.swift`, new files under
`HITList/Support/Delight/` and `HITList/Views/Delight/`, new sound/asset files under
`HITList/Resources/` (add the folder to `project.yml` `sources` ONLY if XcodeGen does not already pick
it up through the `HITList` path; it should), new test files in `HITListTests/`. Do not touch
`SettingsView.swift` (another session owns it): put the user-facing toggles in a new
`DelightSettingsSection: View` (a `Section` with "Completion sound" and "Haptics" toggles bound to
`AppGroup.defaults` keys `delight.sound`, `delight.haptics`, both default on) and say in your final
message that it needs one line in SettingsView to appear; George's main session will add it.

## Task, three commits
1. **Sound + haptics.** A `CompletionFeedback` service: plays a short (≤ 300 ms) custom sound with
   `AVAudioPlayer` using the ambient category so it respects the silent switch and never interrupts
   music; `.success` haptic on iOS (`UINotificationFeedbackGenerator`), `NSHapticFeedbackManager`
   `.levelChange` on Mac. Generate the sound yourself (a two-note soft "tick-ding", sine/triangle with a
   fast decay, 44.1 kHz, m4a or caf; Python with numpy + `afconvert` works) and commit it. Preload on
   first use. Honour the two toggles.
2. **Animation.** In `TaskRow`, the checkbox fills and pops (scale 1.0 → 1.15 → 1.0, ~250 ms, spring),
   the title strikes through left-to-right (mask animation, ~200 ms), the row's background flashes
   `Theme.accent` at 12% opacity, then after ~600 ms the row collapses out of the list (height + opacity).
   During the delay the task is already marked complete in the model (so sync is immediate), but the
   list keeps showing it via a `recentlyCompleted: Set<UUID>` held in the list view until the animation
   ends. Un-completing from a completed-tasks view uses a simpler fade-in. Must be smooth on both
   platforms; reduce to a cross-fade when `accessibilityReduceMotion` is on. Rapidly completing several
   tasks must not drop frames or lose any completion.
3. **Undo toast.** After a completion, a slate toast at the bottom "Completed 'Title' · Undo" for 5 s
   (stacking count when several: "3 completed · Undo"), pressing Undo reverts via
   `TaskActions.toggleCompletion`. Keyboard: ⌘Z while the toast is visible also undoes on macOS.
   Toast is a new view presented from `TaskListView` as an overlay, respects safe areas and the
   QuickAddBar at the bottom (do not cover it; place the toast above it).

## Tests
Unit-test the pure parts: a `CompletionAnimator` state machine (pending → animating → removed, with
cancellation on undo), the toast aggregation text, and that the feedback service does nothing when
both toggles are off. UI behaviour is verified by hand.

## Verify
Signed simulator build and Mac build: complete tasks, undo, complete three quickly, toggle Reduce
Motion, toggle the sound off. Record a short screen recording of the simulator
(`xcrun simctl io booted recordVideo`) and mention its path. Report per COMMON.md.
