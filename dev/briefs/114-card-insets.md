# Brief 114: spacing inside quick add, the editor and every picker card (0.9.6)

Read `dev/briefs/COMMON.md` (the Round 22 block first), then this. **Report due 07:05 Eastern.** Effort: xhigh.

## George's words (2026-11-12, on the pictures of 0.9.5 he was sent)
"Some of the screens in your screenshots still look concerning in terms of text/button spacing, primarily on the
iPhone Duo. It is most obvious in the "Add task" popout and "Reminders" dropdowns, where some text is right next to
a border. This looks lazy and unprofessional. However, many of your edits were still in the right direction, the UI
just needs a bit more work."

George scrutinises spacing to the pixel (`dev/SUPERVISOR.md` §1). The pictures he judged are in
`round-22/george-saw/` in the shared notes folder: `09-duo-cards-…` (the Duo's outer display; the right-hand picture
of each pair is 0.9.5), `07-iphone16-…` (his own phone's size), `06-duo-outer-display-…`.

## What is wrong in them (the supervisor's reading; find the rest by measuring)
- **The reminder card** ("Reminders dropdown"; the editor's and quick add's; the Duo and the iPhone 16): the
  section labels ("Remind me from now", "Remind me before the time") start about 6 pt from the card's border; the
  last chip of a row ("Later today…") ends on the card's right border; the "Add time" field runs from border to
  border; the footnote ("Reminders arrive at the task's time when notifications are on.") starts at the border and
  its last line sits by the card's bottom edge; the "N min" chip is laid out unlike its neighbours.
- **Quick add** ("Add task popout"): the chip row under the title ("+", the date, P1, the reminder) runs to the
  card's right border and the last chip is cut through its words ("11:00 AM · 15"); on the Duo the card and the
  picker above it sit a few points from each other and from the screen's edge.
- **The date card** (quick add's and the editor's): the five quick choices ("Today", "Tomorrow", "Next week",
  "Weekend", "No date") have labels that fill their chips from border to border ("Tomorrow" and "Next week" touch
  both sides), the chips sit 2 to 3 pt apart and about 4 pt from the card; the month's name and the weekday row do
  not share the day grid's left edge; the time field and "Repeat" under the grid.
- **The editor**: its chip row ("Description", "P2", "Reminder", "@waiting") is cut at the card's edge the same
  way; look at every field and row in it.
- Not looked at by anybody yet with this eye: the repeat menu and Custom…, the Group picker, the labels picker,
  the priority choices, the description field, the sub-task rows, the Discard question inside a card.

## The rule (use the design system's tokens; these are floors, on every iPhone and the Duo)
- Text is never closer than **12 pt** to the border of the card, sheet or popover it is in (left, right, top,
  bottom); 16 where the card has the room.
- A control (chip, button, field) is never closer than 12 pt to that border either; a field may run the full
  width only if it is drawn as a full-width row of the card on purpose, with its own text 12 pt in.
- Inside a chip or button the label is at least **8 pt** from the left and right border (6 on the side of its
  icon) and visibly centred top to bottom; two neighbouring controls are at least **6 pt** apart.
- A row of chips that is wider than its card scrolls: it then ends in a fade at the card's inner edge, never a
  hard cut through a word at the border; where the chips can fit by wrapping to a second line or by a shorter
  label, prefer that on a narrow card.
- Things in one card share left edges: labels, chips' first column, fields, footnotes.
- A label that does not fit its chip at the floor gets a wider chip, a second row or a shorter word ("Next wk" is
  not one): never less padding.
- Nothing may get worse on the Mac, where these pickers are the same code: show the Mac's card before and after
  for every card you change (`scripts/window-shot.sh`, `scripts/window-drive.sh`, a Debug Mac app of your own).

## Items, in this order
1. **A way to measure**, built first (half an hour at most): something that, for an open card, lists every text
   and control with its distance to the card's border and to its neighbours and fails under the floors. A UI test
   of your own that reads frames (`CardInsetsUITests.swift`; chips may need identifiers), a Debug-only overlay, or
   a script over screenshots: your choice. George judges by eye, so after the tool says yes, look at each card
   enlarged anyway.
2. The reminder card, then quick add, on the Duo's outer display and the iPhone 16. One commit each, with the
   before and after pictures.
3. The date card and the editor.
4. Every other picker and card in `Views/Popouts/` (the list under "Not looked at").
5. If time is left: the same cards at the larger text sizes (XL), where a tight chip gets worse first.

## Ownership
`HITList/Views/Popouts/*` (quick add, `PopoutHost`, the editor and its cards, `Pickers/*`, `PopoutPickers.swift`)
and `HITList/Support/DesignSystem/*` (chip, button and field styles; say in your report what you changed there,
because brief 115's screens use them too), your own tests. Not yours: the screens under the cards, the Flipboard's
cards, Review Inbox, Settings (brief 115).

## Done
- Before and after of every card changed, on the Duo's outer display, the iPhone 16 and the Mac, in
  `114-card-insets/` in the notes folder, each looked at enlarged by you.
- The measuring tool's output for each card, before and after.
- `scripts/test.sh macos` and `scripts/test.sh ios` green once at the end; `DuoCardsUITests` and your own on your
  Duo simulator. The report COMMON asks for, with a list of anything still under the floors and why.
