# Brief 115: spacing on the screens themselves, the Flipboard's cards, Settings and Review (0.9.6)

Read `dev/briefs/COMMON.md` (the Round 22 block first), then this. **Report due 07:05 Eastern.** Effort: xhigh.

## George's words (2026-11-12, on the pictures of 0.9.5 he was sent)
"Some of the screens in your screenshots still look concerning in terms of text/button spacing, primarily on the
iPhone Duo. It is most obvious in the "Add task" popout and "Reminders" dropdowns, where some text is right next to
a border. This looks lazy and unprofessional. However, many of your edits were still in the right direction, the UI
just needs a bit more work."

George scrutinises spacing to the pixel (`dev/SUPERVISOR.md` §1). The pictures he judged are in
`round-22/george-saw/` in the shared notes folder (`06-duo-outer-display-…`: the lower row is 0.9.5; `08-…`,
`09-…`, `07-iphone16-…`, `11-iphone16-lists`). Brief 114 has quick add, the editor and every picker; you have
everything else, the Duo's outer display first, then the iPhone 16.

## What is wrong in them (the supervisor's reading; find the rest by measuring)
- **Browse on the Duo**: beside the title the profile picture, the bolt and the pill (new Group, Settings) are
  packed a few points apart with no rhythm; the saved-filter chips are cut through a word where the bar column
  begins; the Back circle floats in the column over the first rows' trailing ends.
- **The Flipboard on the Duo**: the tiles start about 3 pt left of the title's left edge; a tile's title and its
  "every week" line sit close to the tile's border; "Before Bed +" at the bottom.
- **The switch card** (add or edit a switch): the five choices ("Daily", "3 days", "Weekly", "2 weeks",
  "Monthly") touch each other; "Add time" and "No Switchboard"; the Discard question's "Keep editing" and
  "Discard" sit by the card's right and bottom border.
- **Review Inbox**: "Edit…" by the card's border; the three tiles' labels ("Pick a Group") near their tiles' sides.
- **Rows**: the meta line's parts (date, labels, Group and its dot) and the row's trailing edge beside the bar
  column on the Duo; section headers ("Overdue 1 … Reschedule all to today") against both edges.
- Not looked at by anybody yet with this eye: every Settings page on the Duo (second lines, toggles, the theme
  grid's names), the quick add guide, the tips, toasts, the sharing sheets, the empty states.

## The rule (use the design system's tokens; these are floors, on every iPhone and the Duo)
- Text is never closer than **12 pt** to the border of the card, tile, sheet or popover it is in; 16 where there is
  room. On a screen, text and controls keep the screen's own margin, and everything in one screen shares it: the
  title, the rows, the tiles, the headers have one left edge.
- A control is never closer than 12 pt to its container's border; inside a chip or button the label is at least
  **8 pt** from the left and right border (6 on its icon's side) and centred top to bottom; neighbouring controls
  are at least **6 pt** apart, and controls in a row are evenly spaced.
- A row of chips wider than its space scrolls and ends in a fade, never a hard cut through a word.
- Nothing may get worse on the iPhone 16 or the Mac where the code is shared: show both before and after for what
  you change there.
- You do not edit `Support/DesignSystem/*` (brief 114's): where a shared chip or button style is too tight, pad at
  your call site or tell the supervisor in one message what 114 should change.

## Items, in this order
1. **A way to measure**, built first (half an hour at most): something that lists, for a screen or an open card,
   every text and control with its distance to its container's border and its neighbours, and fails under the
   floors (a UI test of your own that reads frames, `ScreenInsetsUITests.swift`, or a script over brief 93's walk
   pictures: your choice). Then look at each screen enlarged anyway: George judges by eye.
2. The Duo's outer display, screen by screen in the tabs' order: Inbox, Today, Upcoming, the Flipboard and its
   switch card, Browse, a Group, Review Inbox. One commit per screen with before and after.
3. Settings and each of its pages on the Duo; the guide, tips and toasts.
4. The same screens on the iPhone 16.
5. If time is left: the Duo's inner display on its stand-in (`-duoStandIn YES -duoStandInSize inner` on an iPad
   mini) and the larger text sizes.

## Ownership
`HITList/Views/Tabs/*`, `HITList/Views/Duo/*`, the lists and rows (`TaskListView`, `TaskRow`, `ListChrome`,
`Inbox/`, `Upcoming/`), `HITList/Views/Flipboard/*` with its cards, Review Inbox, `SettingsView.swift` and
`Views/Settings/*` (not `ThemeCompanion.swift`, not `AppearanceSettingsSection.swift`: report what is wrong
there), `Views/Help/*`, the sheets, toasts and tips, your own tests. Not yours: `Views/Popouts/*` and
`Support/DesignSystem/*` (brief 114), the companions.

## Done
- Before and after of every screen changed, on the Duo's outer display and the iPhone 16 (and the Mac where
  shared), in `115-screen-insets/` in the notes folder, each looked at enlarged by you.
- The measuring tool's output per screen, before and after.
- `scripts/test.sh macos` and `scripts/test.sh ios` green once at the end; `DuoColumnUITests` and your own on your
  Duo simulator. The report COMMON asks for, with a list of anything still under the floors and why.
