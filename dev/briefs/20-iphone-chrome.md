# Brief 20: iPhone chrome v2: the floating island bar, the "…" menu on every screen, Liquid Glass

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first (especially "Where things stand" and
"Round 4 ownership"), then `HITList/Views/Tabs/*.swift`, `HITList/Views/Popouts/QuickAddEntry.swift`
(`FloatingAddButton`), `HITList/Views/Popouts/PopoutHost.swift`, and the toolbars of `TaskListView.swift`,
`Inbox/InboxView.swift`, `Upcoming/UpcomingView.swift`, `Flipboard/FlipboardView.swift`, `Tabs/BrowseView.swift`.
Build only on the design system (`HITList/Support/DesignSystem/README.md`).

## Why (George, 2026-10-31, after using build 5)
"Settings should be accessible from the top right three dot menu, which should be visible in all panes in
the Mobile app next to the filter options button. The bar on the bottom of the mobile app should be an
ovular/rounded floating island and not connected to the bottom of the screen; this will also naturally raise
it slightly and give it a bit more padding/room for easier thumb positioning. Can we begin to make use of
more minimal/sleek animations, themes, and even Liquid Glass/new iOS features? Cloud sync confirmations with
a very small visual indicator."

## Files you own
`HITList/Views/Tabs/*` (MobileShell, MobileTabBar, BrowseView, plus a new `ScreenMenu.swift`),
`HITList/Views/Popouts/QuickAddEntry.swift`, `HITList/Views/Popouts/PopoutHost.swift`,
`HITList/Views/Popouts/QuickAddPopout.swift` (its card material only), the `.toolbar { … }` blocks (and the
state they need) of `TaskListView.swift`, `Views/Inbox/InboxView.swift`, `Views/Upcoming/UpcomingView.swift`,
`Views/Flipboard/FlipboardView.swift`, new `HITListTests/MobileChromeTests.swift`, and the ROADMAP row named
below. Nothing else. `SettingsView.swift`, `SyncStatusViews.swift`, `Theme.swift`, `HITTokens.swift` and the
design-system components belong to sessions 21 and 22 running at the same time; read them, never edit them.

## Know before you start
- Deployment targets stay iOS 18 / macOS 15. Liquid Glass is iOS 26+: guard every use with
  `if #available(iOS 26, *)` and keep the slate look as the fallback. Confirmed in the Xcode 27.1 SDK
  (`SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface`): `glassEffect(_ glass: Glass = .regular, in shape:
  some Shape)`, `Glass.regular`, `.tint(_:)`, `.interactive()`, `GlassEffectContainer(spacing:content:)`,
  `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`, `glassEffectTransition(_:)`,
  `.buttonStyle(.glass)` / `.glassProminent`, `scrollEdgeEffectStyle(_:for:)`, `backgroundExtensionEffect()`.
  If a name does not compile, grep that interface file before guessing another.
- Session 22 is adding `hitGlass(in:tint:)` to the design system (glass on iOS 26 / macOS 26 when effects
  are allowed, slate fill otherwise). It is not on master yet: write your own small guard in `MobileShell`
  (one function, one place), so Fable can swap it for `hitGlass` at merge time.
- Honour `Preferences.reduceEffects` (`HITList/Support/Preferences.swift`, read with
  `@AppStorage(Preferences.reduceEffects, store: AppGroup.defaults)`) and the system's Reduce Transparency
  (`accessibilityReduceTransparency`): either one means no glass, no blur; plain `Theme.surface`.
- `Preferences.startTab` / `startTabDefault` hold the tab the shell shows at launch (session 21 builds the
  Settings control; you read the key).
- `SyncIndicatorDot` (`HITList/Support/SyncStatusViews.swift`) is the 6 pt sync dot, already written. Place
  it; do not restyle it.
- `MobileShell` keeps the bar and the "+" in a `safeAreaInset(edge: .bottom)` today; the quick-add card
  docks above the keyboard and `PopoutHost`'s toast pads 136 pt on compact to clear the chrome.
- The simulator for checking: iPhone 17 (iOS 26). George's phone runs iOS 26; the Mac is unaffected by
  this brief except that nothing may regress there (the sidebar keeps its gear for Settings).

## Task, in commits
1. **Island tab bar.** `MobileTabBar` becomes a floating capsule (continuous corners, radius = half its
   height), inset `HITSpacing.l` from both sides and sitting `HITSpacing.s` above the home indicator, about
   64 pt tall so the four targets are thumb-sized, with a hairline `Theme.separator` border and a soft shadow.
   Lists scroll underneath it: content shows through the gap around the island and the last row can still
   be scrolled fully clear of it (use `contentMargins`/`safeAreaPadding` on the scrolled content rather
   than opaque insets; check Inbox, Today, Upcoming, Browse, a pushed Group, the Flipboard, and Completed).
   The selected tab's icon and label stay accent; keep `TodayTabIcon` and `onReselect`.
2. **Glass.** On iOS 26 the island and the oval "+" share one `GlassEffectContainer`; the island is
   `.glassEffect(.regular.tint(Theme.surface.opacity(0.6)), in: .capsule)`, the "+" is
   `.glassEffect(.regular.tint(Theme.accent).interactive(), in: .capsule)` (or `.buttonStyle(.glassProminent)`
   if it reads better), and the quick-add oval card (`QuickAddPopout`, floating style only) gets the same
   regular glass over its slate so the dimmed list shows through faintly. iOS 18 and Reduce
   Transparency/Reduce Effects: today's slate fills, unchanged. Text on the "+" stays `HITColor.onAccent`.
3. **The "+" above the island.** Same trailing inset as the island, `HITSpacing.m` above it; it still hides
   while a popout is up; the toast in `PopoutHost` clears the new chrome height (measure it, don't hard-code
   a second number; expose the chrome height from `MobileShell` through a preference or environment value).
4. **`ScreenMenu`: the "…" on every iPhone screen.** One shared view placed as the last trailing toolbar
   item on Inbox, Today, Upcoming, Browse, every pushed screen (Group, label, filter, Completed) and the
   Flipboard, compact width only (`horizontalSizeClass == .compact`; iPad and Mac keep what they have).
   Contents, top to bottom: a screen-specific section passed in as a `@ViewBuilder` (Inbox: Process…;
   Flipboard: Add switch…, Flip sound; a Group/label/filter: Edit…, which opens the existing editor sheet),
   then "Settings…" (presents `SettingsView().slateSheet()`), then "Version 0.2.0 (6)" as a disabled line
   (`AppInfo.versionLabel`). The label is `Image(systemName: "ellipsis.circle")` with `SyncIndicatorDot()`
   overlaid at its top-trailing corner, offset 1–2 pt outside the glyph so it reads as a badge; the dot has
   its own accessibility label, so the button's label is just "More".
5. **The filter/view options button beside it.** Every list screen keeps a second trailing control to the
   left of the "…": `Image(systemName: "line.3.horizontal.decrease")` opening the view options menu that
   `TaskListView` already has (Show completed, Sort placeholders) and that Inbox needs too (its eye toggle
   moves in here as "Show completed"). Inbox's "Process" button moves into the "…" screen section so the
   trailing area is exactly two icons everywhere. Keep ⌘⇧C.
6. **Start tab.** `MobileShell` reads `Preferences.startTab` once at launch for its initial tab (fall back to
   Today for an unknown value).
7. **Motion.** The bar's press dip, the "+" show/hide and the tab switch use `HITMotion` (standard/spring);
   nothing bounces more than the spring already does; Reduce Motion collapses them to fades.
8. **Tests** (`MobileChromeTests`): the island's metrics (inset, radius = height/2, gap above the home
   indicator) as pure values; `ScreenMenu` instantiates for every `MobileTab` and for a pushed Group and
   contains Settings (render with `ImageRenderer` or just build the body the way `DesignSystemTests` does);
   `startTab` fallback; glass disabled under Reduce Effects (a pure `usesGlass(available:reduceEffects:
   reduceTransparency:)` function). Run `scripts/test.sh core macos ios` before every commit that touches
   layout; the iOS suite takes about ten minutes, so batch.
9. **ROADMAP.** Add one row to the second table: "iPhone chrome v2 (island bar, '…' menu with Settings and
   sync dot on every screen, Liquid Glass on iOS 26)" with status and what you verified.

## Verify running
Build and launch on the iPhone 17 simulator; record a short video (`xcrun simctl io booted recordVideo`) of:
each tab with the island floating and content scrolling under it; the "+" opening the glass card over the
dimmed list; the "…" on Today, on a pushed Group, on the Flipboard; Settings opening from it; the sync dot.
Then once with Reduce Transparency on (Settings → Accessibility → Display & Text Size) to show the slate
fallback. Put the video path in your report. Also build for macOS and confirm the sidebar and Settings are
unchanged there.

## Report
What changed per commit; test counts before and after; the video path; the branch name; anything George
must do or decide (for instance whether the "+" should be glass-prominent accent or plain glass).
