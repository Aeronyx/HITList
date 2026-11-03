# Brief 33: haptics, the Undo toast, add buttons, type size, Mac reopen (branch `feel-and-chrome`, effort High)

Read `briefs/COMMON.md` first. Sessions 31 (parser, `QuickAddPopout` suggestion row) and 32 (task editor,
subtasks, `TaskPopout`, `QuickAddPopout` option bar) run at the same time. Your `QuickAddPopout` edit is one
line: the haptic on the confirm pill's action.

George's words, from the 0.4.0 (13) feedback on 2026-11-03:

> Can the Mac app be any snappier to appear when closed but not quit? Other apps appear again as soon as I
> click them, but HITList takes a second to appear even when it's running in the background.

> Make the plus "Add task" button a good bit larger on mobile and decently smaller on Mac.

> On mobile, add a slight, staccato haptic bump for clicking the "Add task" button, "Confirm add task"
> button, or completing a task. For completing a task, it seems there already are haptics, but it should
> be just one staccato bump, not two.

> The "Undo" button popup at the bottom should be entirely clickable to undo a task, not just the "Undo"
> text. Also, this button should be a bit taller and not as wide/slim, and pop up to the left of the add
> task button, not awkwardly above it. I should also be able to swipe it away. (Most of these are of course
> mobile changes, but as with other changes, make the same ones to the desktop app to ensure buttons and
> animations match wherever practical.)

> The standard font size for tasks is a little too large, and the kerning is ever so slightly too much.
> By like a pixel.

## Items (one commit each)

1. **Mac reopen** (`SyncAppDelegate.swift` Mac half, `HITListApp.swift`, maybe a small `MacWindowKeeper`):
   closing the last window with the red button and clicking the Dock icon (or ⌘Tab) takes about a
   second today because SwiftUI tears the window down and rebuilds `ContentView` and its queries.
   Make the window reappear at once: keep it alive and hidden on close (`NSWindowDelegate.windowShouldClose`
   → `orderOut`, return false; `applicationShouldHandleReopen` → `makeKeyAndOrderFront`), or whatever
   measured approach gets the window back in one frame. ⌘Q still quits; the stuck-sync relaunch
   (`SyncRecovery`) and the scene-phase sync hooks must keep working (check `CloudSyncMonitor.sceneChanged`
   still sees background/active, or call it yourself). Measure before/after with `/usr/bin/log` timestamps
   or a `Date()` print in a Debug run and put the numbers in the report.
2. **Add buttons** (`QuickAddEntry.swift`): iPhone `FloatingAddButton.size` a good bit larger (try 76 × 50
   with a 28 pt glyph; keep `IslandMetrics` in step so the lists' bottom margin and the toast clear it);
   Mac toolbar "+" decently smaller (the `ProminentToolbarButton` frame, e.g. 18 × 13 with an 11 pt glyph;
   do not reintroduce `.controlSize(.small)`, which split the glass oval in build 10).
3. **Haptics** (iOS only; `CompletionFeedback.swift`, a new `Support/Delight/TapHaptic.swift`): one staccato
   bump = `UIImpactFeedbackGenerator(style: .rigid)` (or `.light`, judge on the device description: short,
   single), prepared ahead. Play it on: the "+" add button tap, the confirm pill tap in the quick-add card
   (one call in `QuickAddPopout`'s confirm action), and task completion in place of today's `.success`
   notification haptic (two bumps). Honour the existing Haptics toggle in Settings.
4. **Undo toast** (`CompletionToast.swift`, `PopoutHost.swift`'s `completionToast`/`ListCompletionToast`,
   `TaskListView` where it sizes): the whole pill is the Undo button (one `Button` around the content,
   `.plain` style, pressed state darkens); taller (≈ 48 pt) and narrower (content-sized, max ≈ 60 % of the
   width); on the iPhone it sits to the left of the "+" oval on the same baseline, not above it; swipe
   down or sideways dismisses it (drag gesture with a short fling, `HITMotion` roles). Mac: same pill,
   bottom-right beside where the Mac's add control sits (or bottom-trailing of the list), ⌘Z still undoes,
   clicking anywhere on it undoes, a drag dismisses. Both platforms: the toast must never cover the "+".
5. **Type** (`HITTokens.swift`, `TaskRow.swift`): `HITType.taskName` one step smaller on the iPhone (20 → 19,
   George said "a little"; keep the Mac at 15, which George set after finding 14 too small) and a touch
   tighter tracking (`.tracking(-0.3)` or the Inter static cut's own; "by like a pixel"). Keep `ListMetrics`
   and the row's line height in `TaskRow` consistent (lineHeight 22 → 21 on iPhone). Check the Inter static
   cuts note in `COMMON.md` before changing weights.

## Ownership
`HITList/Services/Sync/SyncAppDelegate.swift` (Mac half only), `HITListApp.swift` (window/delegate lines only),
new Mac window helper file; `QuickAddEntry.swift`; `Support/Delight/CompletionFeedback.swift`, new
`TapHaptic.swift`; `Views/Delight/CompletionToast.swift`, `CompletionMotion.swift`; `PopoutHost.swift` (toast
placement and gesture only); `TaskListView.swift`, `InboxView.swift`, `UpcomingView.swift` (toast call sites
only); `QuickAddPopout.swift` (one haptic call); `Support/DesignSystem/HITTokens.swift`, `IslandMetrics`;
`TaskRow.swift` (line height only; session 32 edits its meta line); `project.yml` only to add files, then
`xcodegen generate`; tests `DelightTests`/`PopoutTests` where they cover these; ROADMAP row "Haptics, Undo
toast, add buttons, type size, Mac reopen (brief 33)".

## Done
All three suites green; iPhone 17 simulator screenshots: larger "+", toast beside it after a completion,
swiped away; Mac: smaller "+", toast beside the list's corner, window back instantly after close + Dock
click (numbers in the report). Haptics cannot be felt in the simulator: say so and show the call sites.
