# Brief 22: Motion, themes and Liquid Glass in the design system

Effort: High. Model: Opus 5.5. Read `briefs/COMMON.md` first (especially "Where things stand" and
"Round 4 ownership"), then `HITList/Support/Theme.swift`, `HITList/Support/DesignSystem/HITTokens.swift`
(`HITMotion`, `HITColor`), the rest of `HITList/Support/DesignSystem/`, `HITList/Support/Preferences.swift`,
`HITList/Views/Settings/AppearanceSettingsSection.swift`, `HITList/Views/TaskRow.swift` and
`HITList/Views/Delight/*`.

## Why (George, 2026-10-31, after using build 5)
"Can we begin to make use of more minimal/sleek animations, themes, and even Liquid Glass/new iOS
features?" The app stays dark: themes are dark palettes with their own accent, never a light mode.

## Files you own
`HITList/Support/Theme.swift`, `HITList/Support/DesignSystem/*` (components, `HITTokens.swift`, README,
gallery), `HITList/Views/Settings/AppearanceSettingsSection.swift`, `HITList/Views/TaskRow.swift` (its
animations and colours only; the layout was just fixed, leave the frames alone), `HITList/Views/Delight/*`,
`HITListTests/DesignSystemTests.swift`, `HITListTests/CompletionAnimatorTests.swift`, new
`HITListTests/ThemeTests.swift`, and the ROADMAP row named below. Add preference keys as
`extension Preferences` in `HITList/Support/DesignSystem/ThemePreferences.swift`; never edit
`Preferences.swift`. Not yours: `Tabs/*`, `Popouts/*`, `SettingsView.swift`, the Services, `project.yml`,
`HITListApp.swift`, `Models.swift`.

## Know before you start
- `Theme` is an enum of static `Color`s used in several hundred places; `HITColor` adds text, onAccent,
  track/thumb, danger and the due colours; `HITMotion.standard` (150 ms ease) and `.spring` are the two
  motion tokens, each with a Reduce Motion variant. `Preferences.theme` ("slate" default) and
  `Preferences.reduceEffects` already exist; session 20 reads `reduceEffects` for its chrome, so the key
  and its meaning (true = no glass, no blur, calmer motion) are fixed.
- Deployment targets stay iOS 18 / macOS 15. Liquid Glass is iOS 26 / macOS 26: `if #available(iOS 26,
  macOS 26, *)`. Names confirmed in the Xcode 27.1 SDK interface: `glassEffect(_:in:)`, `Glass.regular`
  `.tint(_:)` `.interactive()`, `GlassEffectContainer(spacing:content:)`, `glassEffectID(_:in:)`,
  `glassEffectTransition(_:)`, `.buttonStyle(.glass)` / `.glassProminent`, `scrollEdgeEffectStyle(_:for:)`.
  Grep `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface`
  before guessing any other name.
- Session 20 is glassing the iPhone tab island, the "+" and the quick-add card at the same time; you do
  the design-system components, so both read as one material: agree on one helper, `hitGlass(in:tint:)`
  (a ViewModifier in `HITTokens.swift` or a new `HITMaterial.swift`) that applies the glass on iOS 26 /
  macOS 26 when effects are allowed and a slate fill otherwise. Write it first and commit it first: session
  20 is told to use `hitGlass` if it exists on master by the time it merges, and its own guard otherwise.
- The completion animation (`CompletionAnimator`, `TaskRow`'s pop, the strike sweep, the slide-away) is
  George's favourite part; make it crisper, not smaller.

## Task, in commits
1. **`hitGlass` and the motion roles.** `HITMotion` grows named roles with durations that read as quick and
   deliberate: `quick` (100 ms, hover and press), `standard` (150 ms, state changes), `enter`/`exit`
   (200 ms / 150 ms ease-out/ease-in for things appearing and leaving), `emphasis` (the one spring, less
   overshoot than today: response 0.28, damping 0.8), and `celebrate` (the completion check only). Each
   has a `(reduceMotion:)` variant. `hitGlass(in:tint:)` as above. Document both in the README.
2. **Motion audit.** List every `.animation(`, `withAnimation(`, `.transition(` and `.symbolEffect(` in the
   app (grep; include files you don't own) and put the list in your final report as a table (file, what it
   animates, today's curve, the role it should use); write no separate document. In the files you own, switch each to its
   role; anything that bounces, overshoots or lasts over 250 ms outside `celebrate` goes. Hover highlights
   fade with `quick`; segment highlights and toggle thumbs use `emphasis`; the design-system gallery shows
   each role once with a label.
3. **Themes.** Four dark palettes, each a `ThemePalette` (background, surface, elevated, separator, accent,
   secondaryText, text, onAccent): **Slate** (today's values, the default), **Graphite** (neutral greys,
   accent a warm off-white `#E6E1D6` with dark onAccent), **Midnight** (blue-black `#0B0F1A` family, accent
   cyan `#4FD1E8`), **Moss** (green-black, accent `#8FD694`). Due colours and priority colours stay the same
   in every theme. `Theme.background` etc. keep their names and become computed from the current palette so
   no call site changes; switching applies live (an `@Observable` `ThemeStore` in the environment with
   `.id(theme)` on the root view is acceptable; whichever way, state it in the report and keep the Mac
   Settings window updating too). The palette is stored at `Preferences.theme`. Contrast: every
   text/background pair in every palette passes WCAG AA for its size; test it with `Color.resolve`.
4. **Appearance settings.** Fill `AppearanceSettingsSection`: a row of four swatches (a 44 pt rounded square
   showing background, surface and accent, the name under it, the selected one ringed in its accent),
   "Reduce effects" toggle (`Preferences.reduceEffects`) with the footer "Turns off glass, blur and the
   larger movements. HITList also follows Reduce Motion and Reduce Transparency." Session 21 owns the rest
   of Settings and keeps calling your view.
5. **Glass in the components.** With effects allowed on iOS 26 / macOS 26: `HITSheetChrome`'s header bar and
   the Mac popout panel background (if the panel's background is a design-system modifier; otherwise skip
   and say so), `HITSegmented`'s moving highlight, the hover fill of `HITChip`, and the Settings sheet's
   bar; `scrollEdgeEffectStyle(.soft, for: .top)` on `HITSheetChrome`'s scroll view. Everywhere else stays
   slate; glass is a highlight, not a wallpaper. Under Reduce Effects / Reduce Transparency: unchanged
   from today.
6. **Completion.** In `TaskRow` and `Delight`: the check pop uses `celebrate`; the strike sweep stays at
   200 ms; the slide-away and the toast use `exit`/`enter`; the symbol swap gets `.symbolEffect(.bounce,
   value:)` only if it looks better in the recording (your call, say which).
7. **Tests** (`ThemeTests`, `DesignSystemTests`): every palette has eight colours, Slate equals today's hex
   values exactly, AA contrast for text/secondaryText on background/surface/elevated and onAccent on accent,
   `hitGlass` disabled under Reduce Effects (pure decision function), each `HITMotion` role's duration is
   at most 250 ms except `celebrate`, the gallery renders. `scripts/test.sh core macos` before each commit,
   `ios` before the last.
8. **ROADMAP.** Add one row to the second table: "Motion roles, four dark themes, Liquid Glass in the design
   system" with status and what you verified.

## Verify running
iPhone 17 simulator and the Mac: switch all four themes in Settings and record each screen (Today, a
Group, Settings, the Flipboard) for a second per theme; show one completion in Slate; show a sheet's glass
header and the same with Reduce Transparency on. Put the paths in the report.

## Report
What changed per commit; the motion table; test counts before and after; which glass spots you did and
which you skipped and why; the branch name; anything George must decide (palette names, whether Graphite's
off-white accent reads well on the "+").
