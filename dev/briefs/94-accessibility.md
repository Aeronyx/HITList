# Brief 94: everything can be reached, read and pressed (session `accessibility`, effort xhigh)

George, 2026-11-11, 03:35, going to bed:

> please continue reviewing, improving, and hardening HITList until ~8am ET

The roadmap's item (`dev/ROADMAP.md`, Next, 4):

> **Accessibility pass.** VoiceOver and Full Keyboard Access on the custom pieces: the Mac sidebar rows, the cards
> and pickers, the Flipboard's switches, the companions (hidden from VoiceOver).

HITList draws almost every control itself (George calls default SwiftUI controls "AI slop"), so nothing gets the
system's accessibility for free, and nobody has checked. A friend who uses VoiceOver, or anyone who tabs through
the Mac app, should be able to do everything.

Read `dev/briefs/COMMON.md` (Round 19 block first), `HITList/Support/DesignSystem/README.md`, `dev/briefs/HIG-NOTES.md`
(what Apple asks), `dev/SUPERVISOR.md` §7 (George's decisions stand: this pass changes no look and no behaviour
for someone who uses neither VoiceOver nor the keyboard).

## What to check and put right
1. **The audit the system gives.** XCUITest has `XCUIApplication.performAccessibilityAudit` (read its header in
   the 27.2 SDK for the audit types and how to handle or exclude a finding). Write
   `HITListUITests/AccessibilityAuditUITests.swift`: with `-seedDemoData YES`, walk every main screen, card, picker
   and Settings page on iPhone and run the audit on each; fix what it finds (missing labels, elements with no
   traits, clipped text, targets too small, contrast where a token is at fault: say so, do not repaint the theme),
   and leave the test in the UI suite so it stays fixed. Exclude a finding only with a written reason.
2. **VoiceOver reads sense.** For each custom piece, the label says what it is and its state, the trait says what
   it does, the order follows the screen: a task row (title, due, priority, Group, "completed" or not, with the
   checkbox as an action, not a second stop), the checkbox, the "+" (with or without a companion on it: the
   companion stays hidden), the tab bar, the view options, quick add's field and its highlights, the editor's
   cards, each picker (a day in the calendar says its date and whether it is chosen), the Flipboard's switches
   ("Take meds, off, due 9:00"; flipping is the action), Switchboards, the swipe actions as custom actions, the
   Undo toast (announced when it appears), the sync bolt (its state in words), the theme swatches ("Nord theme,
   selected"), the Settings pages pushed inside the sheet (focus moves to the page's title; Back is reachable),
   the share card if it is merged when you get there.
3. **The whole visible shape takes the press.** Session 86 found that the Mac toolbar's sync bolt takes clicks
   only on a 4 pt strip at its left edge: `SyncBolt` (`HITList/Support/SyncStatusViews.swift`) draws its glyph
   `.offset(x: 12)` inside its toolbar item, so the glyph sits outside the item's bounds, and a toolbar item takes
   clicks only inside them. George asked for the bolt to sit nearer the two controls (that is what the offset is
   for), so the fix keeps it exactly where it is drawn today (measure before and after) and makes all of it
   clickable: most likely the bolt and the pill in one toolbar item with our own spacing. Then look for the same
   fault elsewhere: anything drawn with `.offset`, a negative padding or an overlay outside its own frame that is
   meant to be pressed. On iPhone every target is at least 44 pt (the audit says which are not).
4. **The Mac by keyboard.** With Full Keyboard Access on in your own Debug app's run (System Settings is George's:
   do not change it; use the app's own focus handling and say what you could not turn on): Tab reaches the
   sidebar, the list, the toolbar's controls and every control on each Settings section; arrows move in the
   sidebar and lists; Return and Space activate; Escape closes a card; a focus ring is visible on our own
   controls (the design system's, not the system's blue where we draw the control). Nothing takes the keyboard at
   launch (§7).
5. **Reduce Motion, Increase Contrast, Bold Text, Larger Text**: say what the app does with each today and fix
   only what is broken (text clipped at one size up; a state told by colour alone).

## Ownership
Accessibility modifiers, focus handling and hit shapes in any file under `HITList/Views/` and
`HITList/Support/DesignSystem/`, and `HITList/Support/SyncStatusViews.swift` with the toolbar lines of
`HITList/Views/Tabs/ScreenMenu.swift` and `HITList/Views/MacChrome/*` for the bolt. Brief 93 (`qa-sweep`) is
fixing spacing defects in the same view files while you work: keep each change to the lines it needs so the two
merge, and leave layout to it. New `HITListUITests/AccessibilityAuditUITests.swift`, new `HITListTests/Accessibility*Tests.swift`.
Not yours: `Views/Companions/*` and `Support/Companions/*` (check that a companion is hidden from VoiceOver and
never takes focus; if it is not, say so), the share extension's files, `Services/*`, the models, core, `scripts/`,
`dev/`, `CHANGELOG.md`, `WhatsNew.swift`.

## How to work tonight
Nine sessions share one slow Mac. Your own simulator (`HITList-94`), your own side store (`HITLIST_STORE_SUFFIX=s94`),
`-only-testing` while you iterate, the three suites and your audit once at the end. Nobody answers questions or
system dialogs tonight; never change a system setting or permission; never touch George's `/Applications/HITList.app`.

## Done
A table per piece: what VoiceOver said before, what it says now; what the keyboard could not reach and can now.
The audit's findings, fixed or excluded with the reason. The bolt: where it is drawn before and after (the same),
and the width that takes clicks before and after. What is left for a person with VoiceOver to judge (wording,
order), in plain words. All three suites green, the audit green on a fresh simulator. The branch name; changelog
lines in plain words.
