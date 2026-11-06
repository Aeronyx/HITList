# Brief 47: quick-add highlights on native text views (branch `highlight-engine`, effort xhigh)

Read `briefs/COMMON.md` (Round 11 block) and `briefs/HIG-NOTES.md` first. Five sessions run at the same time.

George's words, 2026-11-05:

> The pointing hand is glitchy over highlights on Mac, it rapidly oscillates between the cursor and the pointing
> hand (mostly staying as the cursor). I also want to make highlights a invisible deletable object that exists in
> front of the highlighted word, e.g. typing "today" highlights to "[today]" but if I were to press backspace after
> typing it (or when I continue typing and then return to it with the cursor) it first removes the highlight
> without deleting a letter. This makes it so the two ways to remove quickadd highlights are by clicking/tapping
> the highlight or by pressing backspace in front of it.

Why it needs a rebuild: the title field is a SwiftUI `TextField` (iPhone/iPad) and a `TextEditor` with AppKit
`ClickTarget` overlays (Mac, brief 41). The `NSTextView` inside `TextEditor` resets the I-beam on every mouse move,
so the overlay's pointing hand flickers; and SwiftUI fields cannot intercept the software keyboard's backspace.

## Items (one commit each, failing test first where there is logic)
1. **Native field** (`TokenHighlightField.swift`, new `Views/Popouts/HighlightText/*`): wrap `UITextView` (iOS) and
   `NSTextView` (Mac) in representables that draw the highlight boxes themselves (TextKit 2 layout fragments or the
   text view's own drawing), so boxes sit exactly on the glyphs at every width, wrap and scroll. Keep everything the
   field does today: joined boxes (37), switched-off phrases by place (41), superseded phrases, placeholder, HITType
   font and tracking, growth to its max lines, paste turning line breaks into spaces, Return rules (36: iPhone Return
   does nothing in the title and the key is a plain "return"; Mac Return and ⌘Return confirm), focus at once on the
   Mac (39's retry), VoiceOver ("Keep “tom 4” as text" actions), the compact board card, sticky drafts, IME/marked
   text (Japanese input must not lose highlights mid-composition), dictation, undo/redo.
2. **Mac pointer** : pointing hand over a highlight box, I-beam elsewhere, from the text view's own cursor handling
   (`resetCursorRects`/`cursorUpdate`/`mouseMoved` in the `NSTextView` subclass), so nothing fights it; no flicker
   when moving inside a box or across joined boxes; a click on a box switches it off (as now), a click elsewhere
   places the caret. iPad pointer: the box's shape. Touch on Mac: a tap on a box switches it off.
3. **Backspace removes the highlight first**: with the caret exactly at the end of a highlighted phrase (or joined
   box) and no selection, Backspace switches that phrase off (the same `onDisable` path as a click) and deletes
   nothing; the next Backspace deletes characters as usual. Works on the software keyboard, a hardware keyboard and
   the Mac. With a space after the phrase, the first Backspace deletes the space (the caret is no longer at the
   phrase's end), the next one removes the highlight. ⌘Z (Mac) / shake or three-finger undo (iPhone) brings the
   highlight back. Tests for the caret rule.
4. **Remove the old overlays** (`ClickTarget`, the SwiftUI rect overlay) once the native field replaces them.

## Ownership
`Views/Popouts/TokenHighlightField.swift`, new `Views/Popouts/HighlightText/*`; `QuickAddPopout.swift` and
`CompactQuickAddCard.swift` only at the line that builds the field (session 48 edits the Reminder chip region of
QuickAddPopout, 49 the compact card's Discard); tests `HighlightAreaTests`, new `HighlightFieldTests`; `project.yml`
only to add files; ROADMAP row "Highlights on native text views (brief 47)". Not yours: `QuickAddDraft.swift` and the
parser (48: the field calls `onDisable`, which already exists), `TaskPopout.swift`.

## Done
All three suites green; iPhone simulator screenshots: "Buy milk today p1" boxed, Backspace once (box gone, text
intact), again (a letter gone); a long wrapped title with correct boxes. Mac: run your Debug app on a side store and
capture its window with `scripts/window-shot.sh` (COMMON): boxes, and a written description of the pointer test
(you cannot move the real pointer: test the cursor rects in a hosted-window test). Report what George should hover.
