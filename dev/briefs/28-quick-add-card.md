# Brief 28: Quick-add card: tappable token highlights, and "sticky" that means only "don't lose it"

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md`, then `HITList/Views/Popouts/TokenHighlightField.swift`,
`QuickAddPopout.swift`, `QuickAddDraft.swift` (including `QuickAddDraftStore`), `QuickAddContext.swift`,
`PopoutHost.swift` (the quick-add overlay, `requestClose`, `DiscardBubble`, `KeyboardObserver`),
`PopoutController.swift`, `HITListCore/Sources/HITListCore/QuickAddParser.swift` (tokens, quoting as an
escape), and the tests `HITListTests/PopoutTests.swift`, `QuickAddDraftStoreTests.swift`.

## George's decisions (2026-11-02)
A. **Tapping a token highlight turns it off.** Every recognised token in the title (dates, times, repeats,
   `#group`, `@label`, `p1`–`p4`, `!15mb`) is highlighted; tapping or clicking the highlight disables that
   token: the words stay as plain text, the highlight goes, the chips no longer reflect it, and the task is
   created with the words in its title. "Call Tom" → tap the "Tom" highlight → a task called "Call Tom"
   with no date. Typing on keeps the choice for that token. Both platforms (iOS `TextField`, Mac
   `TextEditor` today; a `UITextView`/`NSTextView` representable is fine if that is what hit-testing a
   character range needs, as long as Return still submits, the placeholder, focus and the 500-character cap
   survive, and the look is unchanged). Keep the core change in a **new file**
   `HITListCore/Sources/HITListCore/QuickAddParser+Disabled.swift` (an API such as
   `parse(_:disabling:)` that skips the given tokens, identified in a way that survives editing the rest
   of the text, e.g. by kind + matched text); do not edit `QuickAddParser.swift` itself (session 27 is
   changing its date and time logic at the same time).
B. **Highlights look like buttons:** slightly rounded corners (about 4 pt), the same tints as now.
C. **Sticky drafts, redefined.** No drafting system. The only promise: a quick-add card George had open,
   with something typed, is still there when he comes back, including after the app was killed in the
   background. So: the card keeps its state across app switches (it already does); if the app launches
   and a card was open with content when it was last alive, that card reopens itself with its text,
   description, location and deadline, in the same list context it had (`QuickAddContext` needs to be
   stored and restored: make it `Codable`); a card opened fresh from any list never receives a stored
   draft (today it does, from any list: remove that); the stored draft is cleared whenever the card
   closes for any reason (added, Discard, ×, closed empty, Mac panel closed). On iPhone the Discard flow
   stays as it is. Mac: × closes and clears, as today.
D. Return stays idempotent (`hasSavedForClose`); one Return, one task, on every path you touch.

## Files you own
`TokenHighlightField.swift`, `QuickAddDraft.swift`, `QuickAddPopout.swift`, `QuickAddContext.swift`, the
quick-add overlay parts of `PopoutHost.swift` (session 29 edits its task-popout and toast parts: keep to
your region), `PopoutController.swift` (opening a restored card), `HITList/HITListApp.swift` or
`ContentView.swift` only for the one launch hook that reopens a stored card, the new core file, tests
(`PopoutTests`, `QuickAddDraftStoreTests`, new `TokenDisablingTests` in HITListCoreTests), one ROADMAP row.

## Work
Tests first where a pure function exists (parsing with disabled tokens, the draft store round trip with
context, "a fresh card gets nothing"). Build and run the iPhone 17 simulator and the Mac app to check the
tap/click by hand as far as you can (you cannot tap the simulator; drive the Mac app or write a render
test for the field). `scripts/test.sh core macos` after each commit, `ios` before the last. Report: what
changed per commit, how hit-testing works on each platform, test counts, the branch name, anything George
should decide.
