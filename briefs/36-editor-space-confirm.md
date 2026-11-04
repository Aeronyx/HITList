# Brief 36: taller editor, bigger Confirm, confirm only by the button (branch `editor-space-confirm`, effort High)

Read `briefs/COMMON.md` first. Session 35 (iPhone tabs and Browse) runs at the same time; sessions 34, 37 and 38
may already be merged into master when you start (37 changed `TokenHighlightField.swift`'s highlight areas and
the parser; pull nothing, just build on what is there).

George's words, from the 0.4.1 (14) feedback on 2026-11-04:

> Give the "Edit task" pane some more screen space (a pair of screenshots attached to show the
> difference), increase the size of the "Confirm task" button both on the edit screen and the "Add task"
> screen, remove the "Created at ..." line and breakline, and remove the checkmark/confirm button on the
> iOS keyboard, only allow task confirmation via the "Confirm task" button.

The screenshots (not available to you): two of the editor sheet at its medium height on the iPhone 16; the
one George prefers has clearly more room above the Confirm pill, about the height of a card row more.

## Items (one commit each, failing test first where there is logic)

1. **More room** (`PopoutHost.swift` sheet detents, `TaskPopout.swift`): the editor opens taller. Replace or
   raise the medium detent (e.g. `.fraction(0.72)` or a `.height` computed from the content: title,
   description, the chips card, the Sub-tasks card with two lines, and the Confirm pill with ≥ 24 pt of air
   above it), keep `.large`. Measure on the iPhone 17 simulator (same width as George's iPhone 16; a shorter
   screen than the Pro Max) and report the numbers before and after.
2. **Bigger Confirm** (`QuickAddPopout.swift` footer and the editor's footer): one shared size for the
   Confirm pill on both screens, noticeably larger (from today's height and label size to about 48 pt tall
   with a 17 pt semibold label and wider padding; judge it against the "+" oval, which is 76 × 50). If the two
   footers do not already share a component or a constant, make one (`HITTokens`-style constant in a file you
   own, or a small view in `Views/Popouts/`).
3. **No "Created …" line** (`TaskPopout.swift` / `Editor/*`): remove the "Created at …" line and the divider
   above the footer. Keep the creation date reachable in the editor's "…" menu (a disabled menu line
   "Created 3 Nov 2026, 14:02" is enough).
4. **Confirm only by the button** (iOS; `TokenHighlightField.swift`'s `submitLabel` / `onSubmit` lines only,
   `QuickAddPopout.swift` title submit, the editor's title field): the keyboard's blue check/Done key is gone
   (plain `return` key), and Return in a title neither saves nor inserts a newline (a pasted newline still
   becomes a space as today). Sub-task lines keep Return = next line. The Mac keeps its keyboard behaviour
   (Return and ⌘Return as today); say so in the report as a decision George might reverse.
5. **Swiping the editor down keeps your typing safe** (open item from 0.4.1; `PopoutHost.swift`): today a
   swipe down on the editor sheet discards unsaved edits silently. Since saving is now only by Confirm, a swipe
   down with changes asks the same Discard question the quick-add card asks when tapped away (George's rule:
   "tapping away asks Discard whenever the card has any content"); with no changes it just closes.
   `interactiveDismissDisabled` while dirty plus the existing Discard bubble is the likely shape. Test the
   dirty check.

## Ownership

`HITList/Views/Popouts/TaskPopout.swift`, `Views/Popouts/Editor/*`, `QuickAddPopout.swift` (footer and the
title's submit only), `TokenHighlightField.swift` (the `submitLabel`/`onSubmit`/Return handling only; session
37 owns `areas` and the highlight drawing), `PopoutHost.swift` (sheet detents, the editor's dismiss and Discard),
`PopoutController.swift` if the dirty state lives there; tests `PopoutTests` (append; 37 put its tests in a new
file); `project.yml` only to add files; ROADMAP row "Taller editor, bigger Confirm, confirm by button (brief 36)".

Not yours: `Views/Tabs/*`, `BrowseView.swift` (35), Settings and model files (34), `QuickAddDraft.swift`
and the parser (37), `Views/Upcoming/*` (38).

## Done

All three suites green; iPhone simulator screenshots: the editor at its new opening height with the Sub-tasks
card and the larger Confirm pill and air above it; the quick-add card with the same pill; the keyboard with a
plain return key; Return in the title doing nothing; a swipe down with an edit asking Discard, and without one
just closing; the creation date in the "…" menu.
