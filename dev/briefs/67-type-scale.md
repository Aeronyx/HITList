# Brief 67: the type, on iPhone and Mac (session `type-scale`, effort xhigh)

George, 2026-11-08, on 0.8.1 (screenshot `/Users/gtrammell/Desktop/HITList/build.noindex/round-15/george-2-type-ours-top-target-bottom.png`:
our Mac Inbox row on top, "call mom" with "Friday" under it; the target below, "check backlog/longterm" with "Nov 5";
both captured on the same Mac at the same scale):

> The font size on iPhone Duo is now solid, but it actually made me realize that the font size on iPhone and Mac is
> actually too small, and the kerning/weight is not quite right either. The second screenshot shows our font on top and
> the target font on the bottom; notice the subtle differences for both the task name and the Date tag, and improve the
> core font package for both iOS and macOS.

Read `dev/briefs/COMMON.md`, `dev/briefs/ROUND-15.md`, `HITList/Support/DesignSystem/README.md` (type roles) and
`HITList/Support/DesignSystem/HITTokens.swift` (`HITFont`, `HITType`). The history matters: the app is set in Inter
(static cuts, `HITFont.inter`). Rows on the Mac are `HITType.body`, Inter 13. On iPhone rows were 17 until build 13,
when George found them "a little too large" and the kerning "ever so slightly too much, by like a pixel", so they became
16 with −0.3 tracking (commit `e6bf3c6`); the meta line is 12. The Duo's outer display (brief 63) uses 17 and 13 beside
the upright island, and George now calls that "solid". The quick-add card's title is 15 bold on the Mac ("14 was too
small"). SUPERVISOR §7's "Mac rows 15 pt" means that card title, not the rows.

## Items (one commit each)
1. **Measure before changing anything.** From George's screenshot, measure both rows in pixels: x-height, cap height,
   ascender, the stem width of the title and of the date tag, the average advance per character, the gap from the
   title's baseline to the date line, the date icon's size and its gap to the text. Work out what the target is (which
   family it looks like: Inter or the system font, SF Pro; its size and weight on a 2x screen) and how ours differs.
   Render ours at candidate settings on the same scale (an `ImageRenderer` test image or the Debug Mac app captured
   with `scripts/window-shot.sh`) and put them side by side with the target crop. Keep these images and numbers for
   the report.
2. **Choose and apply, through the tokens only.** Change the roles in `HITTokens.swift` so a row's title and its date
   tag match the target as closely as the evidence allows, on the Mac and the iPhone: size, weight (Inter has static
   cuts from Light to Bold; a medium-ish weight may be what "weight" means), tracking per size. If the target is
   clearly the system font and Inter cannot get there, say so with the side-by-side images, and either move the text
   roles to the system font or keep Inter with the closest settings: report which and why, as a decision George may
   reverse. Keep the hierarchy: section headers, large titles, the editor's and quick-add card's titles move with the
   rows so nothing ends up the same size as something it should outrank. The Duo's side sizes keep their place relative
   to the new iPhone sizes (George likes them; if the iPhone's new row size equals the Duo's, they become one).
3. **Rows fit the new type.** `TaskRowMetrics` (in `TaskRow.swift`; only that enum is yours there) and `ListMetrics`
   (`ListChrome.swift`) follow: the checkbox still centres on the first title line, two-line rows do not clip, the board's
   cards and the Flipboard's tiles still fit their titles. Pin the sizes and metrics in a test.
4. **Look at every main screen** on the iPhone 17 simulator and the Mac (`-seedDemoData` on a side store): Inbox, Today,
   Upcoming (list and board), Flipboard, Browse, a Group, the editor, the quick-add card, Settings. Before and after
   screenshots of each, and the side-by-side with George's target for the row.

## Ownership
`HITList/Support/DesignSystem/HITTokens.swift`, `HITList/Support/DesignSystem/README.md` (the type table),
`HITList/Views/ListChrome.swift` (`ListMetrics`), `TaskRowMetrics` in `HITList/Views/TaskRow.swift` (nothing else in that
file: brief 64 changes its meta line), `HITList/Resources/Fonts/*` and their `project.yml` entries if a new cut is needed,
`HITListTests/TypeTests.swift` (or the existing type/metrics tests), your `dev/ROADMAP.md` row.
Not yours: any view file that sets its own font (if one hard-codes a size that should follow a role, list it in the
report and the supervisor moves it after the merge), `SyncStatusViews` (68), `Views/Flipboard/*` (69).

## Done
The measurements, the side-by-side images (ours before, ours after, the target) for the Mac and the iPhone, and the
before/after screenshots of item 4. All three suites green.
