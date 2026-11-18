# 162: quick add's chips in one scrolling row, and tips that hold their shape (code)

George, 2026-11-18: "The tagging options in the 'Add task' popout should be a horizontally scrolling bar, not one
that wraps (e.g. Inbox shouldn't be on the second line in the second screenshot)." His picture: the iPhone's quick-add
card with "+", Date, Priority, Reminder on one line and Inbox alone on a second. And: "some of the tooltips are really
hard to read/need to be more concise/need to have better UI logic so they stop looking broken/changing aspect ratio."

**Yours**: `HITList/Views/Popouts/QuickAddPopout.swift`, `CompactQuickAddCard.swift` (the chips' row only: nothing of
the draft, the parser, the pickers or the title field), `HITList/Views/Tips/`, `HITList/Views/Calendar/CalendarTip.swift`,
tests of your own. Where a tip is attached inside another agent's file (`ScreenMenu`, `FlipboardView`,
`UpcomingBoard`: agent 161's, `TaskListView`), change the one modifier line at most, and say so. **Not yours**:
everything else, `Views/Settings/` (163), `Views/Upcoming/` (161).

## Part 1: the chips

1. **One row that scrolls sideways**, in the quick-add card on iPhone, iPad and Mac and in the compact card: never a
   second line, so the card's height does not change when a chip is added. No scroll indicator.
2. **Done so that it does not look cut.** Round 22 (brief 114) turned an earlier sideways row into the wrapping one
   because "the sideways row ran to the card's border and cut its last chip through its words": George reads text cut
   at a border as careless. So: the row's content starts in line with the title and ends with the card's own padding
   after the last chip (the last chip can always be scrolled whole into view, with the padding beside it); where
   chips continue past an edge, that edge fades over about 16 pt (a mask, both edges, only while there is more that
   way), so a chip leaves softly and never ends in a hard cut; a chip that changes or appears (a date typed, a label
   added) scrolls itself into view. The row's taps, pickers and their anchors work as now; the keyboard and focus
   behaviour of the card do not change.
3. A hosted or UI test: with three labels and a deadline added the card is as tall as with none, and the Group chip
   ("Inbox") is reachable. `CardInsetsUITests` and `ScreenInsetsUITests` measure spacing: run them; where one
   measures the chips' old wrapping, change the test to the new rule (padding after the last chip when scrolled to
   the end) and say so.

## Part 2: the tips (`HITTips`, `HITTipStyle`, `CalendarTip`)

4. **See them first.** With `-showAllTips` (and each tip's real place), a picture of every tip on an iPhone
   simulator and on the Mac, before you change anything: the popover tips, quick add's floating tip, the calendar
   tip over Today. Note for each what is wrong as a friend would see it: a size that changes while it appears or
   as text lays out, a tall narrow or a wide flat shape, text hard to read against its background, a tip over
   the bar or off the screen, an arrow pointing at nothing.
5. **One shape.** Every tip has one width per platform (decide it from the pictures; the iPhone's is the screen's
   width less the margins, up to a maximum), its height from its words, laid out once: its size on the first frame
   is its size for good, with no animation of the frame, in a popover and floating alike.
6. **Fewer words.** A title of at most four words; a message of one sentence, at most about 90 characters, that
   says what to do, not how the feature works; no symbols a friend has to decode. Rewrite each (`HITTipKind`), in
   the app's plain voice. The message in a colour that reads at a glance on `Theme.elevated` in every theme
   (contrast of at least 4.5 to 1: compute it for each theme, do not judge by eye).
7. **Logic.** A tip shows once, never over another tip, a popout or a sheet, never on a first screen (the existing
   settling rule), and goes when its subject is used. If a tip cannot be made to sit well where it is, remove that
   tip and say so: no tip is better than a broken one.
8. Also read every Mac hover text (`.help("…")`) in `HITList/Views`: where one is longer than about 60 characters or
   says the same as its control's label, list it in your report with a shorter wording (change only those in your
   own files).

Proof: the pictures before and after, side by side by name, in your notes folder; `HITListTests` whole on the Mac
once at the end; `QuickAddGuideUITests`, `CardInsetsUITests`, `ScreenInsetsUITests`, `FirstRunUITests` and
`HITListUITests` on your simulator.
