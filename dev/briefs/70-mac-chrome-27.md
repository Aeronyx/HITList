# Brief 70: the Mac looks the same on macOS 26 and 27 (session `mac-chrome-27`, effort xhigh)

George, 2026-11-10, on 0.9.0 (20):

> Mainly, why in the world does my friend's Mac app still look different than mine if he's running the latest macOS
> and I disabled the iPad app thing? So confusing. A screenshot of his version is attached with many concerning subtle
> differences.

> My friend is indeed on Golden Gate 27.2, which is why his app may look odd, but we should still be able to prepare
> for that, no?

Read `dev/briefs/COMMON.md` (Round 16 block first), `dev/briefs/ROUND-16.md` ("The friend's Mac"), `66-mac-chrome.md`
(the toolbar and sidebar search you are hardening) and `dev/briefs/HIG-NOTES.md`.

The two pictures, the same build (0.9.0 (20), built with the Xcode 27.2 SDK):
- his, macOS 27.2: `/Users/gtrammell/Desktop/HITList/build.noindex/round-16/friend-mac-today-0.9.0.png`
- ours, macOS 26.7.1: `/Users/gtrammell/Desktop/HITList/build.noindex/round-15/mac/02-today.png`

**Nobody here has macOS 27.** George's Mac and this machine are 26.7.1, GitHub has no macOS 27 runner, and there is no
VM. So this brief cannot be done by tuning until 27 looks right. It is done by taking each thing the system decides
out of the system's hands: we draw it, or we pin it with an explicit value, so there is nothing left for 26 and 27 to
disagree about. Never write `if #available(macOS 27, *)` guesses. Where you cannot own a thing, say so in the report.

What differs in his picture, and what the supervisor measured (pixels at 2x):
- **The Search field holds the keyboard at launch** (accent ring), so the sidebar's selected row is drawn
  unemphasized: grey `#40454F` with bold text, instead of our accent fill `#688DD4` with regular text.
- **The toolbar zone** (title, bolt, pill, "+") and the strip down to the bottom of the first section header is
  `#252B33` on 27; the header ("Overdue") draws its own `Theme.background` behind itself (`taskSectionHeader`), which
  shows as a dark band `#1B2029` inside it. On 26 the toolbar band is a neutral `#282828` and the header strip is the
  content's own colour, so the band is invisible.
- **The view-options pill** is filled grey glass on 27, an outline on 26. **The sidebar toggle** sits in a filled
  glass circle on 27. **The "+"** sits about 5 pt from the window's right edge on 27, 9 pt on 26.
- **The sidebar** is flush with the window's left and top edges on 27, with a hairline at its right; on 26 it is a
  floating rounded panel. Its icons are larger on 27.
- **`@flipboard`** is green in his rows, grey in ours. Probably his label has a colour (`Flipboard.label(in:)`) and
  the demo seed's has none: find out which and say so; fix it only if a label's colour really is drawn differently.

## Items (one commit each, failing test first where there is logic)
1. **Nothing takes the keyboard at launch.** When the window opens, comes back, or becomes key again with no
   deliberate focus, no text field is the first responder: not the Search field, not anything else. ⌘F and a click
   still focus Search; Tab still reaches it; Escape still lets go. Pin it: a hosted test that the window's first
   responder is not a text view after the content appears, and a Debug launch argument (`-focusSearchAtLaunch YES`)
   that forces the bad case so items 2 and the screenshots can prove the sidebar does not change with it.
2. **The sidebar's rows and selection are ours.** Today `SidebarView` is `List(selection:)` in `.listStyle(.sidebar)`:
   the system draws the selection (accent or grey by first responder and window state, bold on 27), sizes the icons
   (System Settings → Appearance → Sidebar icon size, and the OS version) and sets the row metrics. Draw all of it:
   explicit `HITType` fonts and weights, explicit icon sizes, explicit row height and insets, our own hover and our
   own selection fill, the same whether the window is key, whichever view holds the keyboard, and on any macOS. The
   look to match is ours on 26.7.1, pixel for pixel where you can (overlay before and after): accent fill, regular
   weight, the counts as they are. Keep everything the list does today: arrow keys move the selection, context
   menus, dragging Groups and Filters to reorder, the "Groups +" headers, the Shared Tasks row, the Settings button
   at the foot, `MacSettingsSidebar` (give it the same rows). How is yours to choose (a `List` without `selection:`
   and a plain style, or a scroll view of rows), but nothing may depend on the sidebar list style's own drawing.
   The iPad keeps its `List` as it is.
3. **The detail column is one colour, set by us.** Give the window toolbar an explicit background
   (`Theme.background`, visible) so the toolbar zone, the first section header's strip and the list are the same
   slate on every macOS: no neutral grey band (26), no lighter strip with a dark band in it (27). This changes
   George's own Mac too (the grey band becomes slate): show before and after in the report. Check every Mac screen
   that has a first header or none: Inbox, Today with an Overdue section (`-seedDemoData` has overdue tasks; if not,
   move a task's date back), Upcoming's board, the Flipboard, a Group, Completed, Search results, Settings.
4. **The toolbar's controls are drawn by us.** The view-options pill (two controls in one capsule) gets our own
   capsule, drawn like the "+" was in round 15 (the Confirm pill's look, `HITButtonStyle` family), with the system's
   shared glass hidden for that group, so it is not an outline on one macOS and filled grey on another. Same size
   and place as today on 26 (`ScreenControlMetrics`). Replace the system's sidebar toggle with our own button (same
   glyph, same place, toggling the split view), so it has no glass circle anywhere. Give the trailing items an
   explicit inset from the window's edge if the toolbar lets you pin one; if not, report it.
5. **The sidebar column's background reaches every edge it can.** `Theme.surface` behind the whole column including
   the strip under the traffic lights, so a flush sidebar (27) and a floating one (26) are both plain slate with no
   system material showing through. Do not replace `NavigationSplitView` in this brief: whether the column floats or
   sits flush stays the system's. Say in the report what it would take to own that too (our own split and top bar),
   so George can decide.

## Ownership
`HITList/Views/SidebarView.swift`, `HITList/Views/ContentView.swift` (the Mac's `SplitContent`),
`HITList/Views/Tabs/ScreenMenu.swift` (the Mac branch; the iPhone's stays), `HITList/Views/Popouts/QuickAddEntry.swift`
(the Mac toolbar item only), `HITList/Views/Search/*`, `HITList/Views/ListChrome.swift` (`taskSectionHeader`),
`HITList/Views/Settings/Mac/MacSettingsPage.swift` and `MacSettingsSection.swift` (the sidebar's rows),
`HITList/Support/MacWindowKeeper.swift`, the window lines of `HITList/HITListApp.swift`, new files under
`HITList/Views/MacChrome/`, `HITListTests/MacChromeTests.swift`, `HITListTests/MacSearchTests.swift`,
`HITListTests/MacSettingsTests.swift` (rows only), the design system README if you add a component, your
`dev/ROADMAP.md` row. Keep `SidebarSectionHeader`'s and `SidebarCounts`' interfaces: `BrowseView` (brief 73) and the
lists call them.
Not yours: `Views/Flipboard/*`, the models and core (72); `BrowseView`, `Views/Groups/*`, `SyncStatusViews`,
`BoltSlamMotion` (73); core's parser (71); `TaskRow`, `HITTokens`; `CHANGELOG.md`, `WhatsNew.swift`, `scripts/`.

## Done
Mac screenshots (`scripts/window-shot.sh`, demo data), each beside the same screen from master before your first
commit: Today with Overdue, Inbox, Upcoming, Flipboard, a Group, Search results, Settings; the sidebar with the Search
field focused (`-focusSearchAtLaunch YES`) and with the window in the background, selection unchanged in both. A
table in the report: each thing in the Mac window the system still decides after your work (the split view's shape,
the traffic lights, the toolbar's insets, menus), and for each whether 27 can differ. All three suites green.
