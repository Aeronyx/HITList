# Brief 99: the Mac's "…" becomes Settings, and the sweep's findings (session `sweep-polish`, effort xhigh)

George, 2026-11-11, after 0.9.3, on last night's findings (`build.noindex/round-19/qa-sweep/FINDINGS.md` in the
main checkout, `/Users/gtrammell/Desktop/HITList/`; its pictures are beside it) and on the Mac's toolbar:

> * Mac settings: I agree with your recommendation.
> * Mac data: three columns of two is good, whatever fits best.
> * About: Earlier versions isn't even a necessary feature.
> * Sync log: agree.
> * Honestly, I'm not going to read the rest of these; most of them have obvious answers, and if they really don't
>   ask me directly in the chat.
>
> The top right (...) button on Mac should just be the Settings button in most/all menus.

George scrutinises spacing to the pixel. Every item below is small; each is one commit with a before and an after
crop and, where it is a number, a pin in `SpacingTests` or the screen's own layout test. Read
`dev/briefs/COMMON.md` (Round 20 block first), `dev/SUPERVISOR.md` §7 (do not undo a decision),
`HITList/Support/DesignSystem/README.md`, `dev/briefs/HIG-NOTES.md`, and the findings file.

## Items
1. **The "…" is the Settings button** (Mac, and iPad, which shares the code: `Views/Tabs/ScreenMenu.swift`). The
   toolbar pill's second control becomes a gear that opens Settings at once: no menu. What the "…" held besides
   "Settings…" moves under the view options' divider, as on iPhone (`screenMenuItems`); the version line goes (it
   is in Settings → About). Give the table: each screen, what its "…" held, where each item is now. If a screen
   has an item with no sensible home in the view options, keep that screen's "…" and say why ("most/all"). The
   gear reads "Settings" to VoiceOver and in its tooltip; ⌘, is unchanged; the sidebar's own Settings row stays.
2. **Mac Settings: a section's name once.** Keep the page's big header; the toolbar title is empty on the Settings
   page (George agreed).
3. **Mac Data: Library's six tiles** sit three across in two rows at every width that fits them, never five and
   one.
4. **"Earlier versions" goes** (About, both platforms, and the What's New popout's expanding list): What's New
   shows this version's notes only. The supervisor keeps the entries in `WhatsNew.swift`; do not delete them.
5. **Sync log: the filters are not buttons.** "All" and "Errors" become the design system's segmented control;
   "Copy log" and "Save…/Share…" stay capsules (`Views/Settings/SyncLogView.swift`).
6. **Mac Upcoming board: one left edge.** The month's name (16 pt in), the cards (22) and the day headers (26)
   share the cards' edge.
7. **A day reads one way everywhere**: "Nov 11 · Today · Wednesday" (the date, then Today, Tomorrow or Yesterday
   when it is one, then the weekday), in Today's header, a Group's date sections, Upcoming on iPhone and iPad and
   the Mac board. Today four forms exist ("Nov 11, Wednesday", "Friday, Nov 13", "Wed · Nov 11 · Today", "Nov 11 ·
   Today · Wednesday"). One formatter, tested; the weekday shortens to three letters only where the full line does
   not fit at the largest ordinary text size.
8. **The Mac sidebar shows no header over nothing**: "Filters" hides while there are no saved filters, unless the
   header itself carries the only way to add one (then say so and leave it).
9. **"Done" is the accent pill everywhere**: the What's New popout and Send Beta Feedback (grey text today),
   Review Inbox (an outlined capsule today). What's New's header reads "Version 0.9.4", not uppercase.
10. **One section-header style.** Browse's headers ("Groups +") and Settings' ("Appearance") are two styles;
    §7 says one. Make them one component in the lists' style. Settings' first screen must still fit an iPhone 17
    and an iPhone 16 (393 × 852) without scrolling (`SettingsTidyTests` pins it): if the lists' style cannot fit,
    show both in your report and keep the layout that fits.
11. **No hairline between a large title and the first row** (Inbox and Completed draw one 1 pt under the title;
    Today, Upcoming and a Group do not).
12. **Rows share the large title's left edge on every iPhone width.** On wide phones the system draws the large
    title at its 20 pt margin while our rows and headers sit at `ListMetrics`' fixed 16 (seen on the Duo's outer
    display; the Pro Max by the same rule). Rows, headers and the empty-state line follow the system's margin: 16
    where it is 16 (iPhone 17, George's iPhone 16: nothing moves there, prove it on rendered pixels), 20 where it
    is 20.
13. **Duo outer display:** Browse's filter chips scroll under the trailing bar; they stop at the safe area.
14. **iPad sidebar:** the selected row is our own fill, as on the Mac, not the system's accent outline.
15. **Text sizes:** at the largest ordinary size "Tokyo Night" truncates under its swatch (it must not); at the
    smallest, captions and meta lines never go below 11 pt.
16. **Reminders → Summary time** uses our own time field (`Views/Popouts/Pickers/PickerTimeField.swift`, used as it
    is; brief 97 owns the pickers) instead of the system's picker.
17. **Mac editor:** the check circle's hit frame is 24 × 24 (22 × 24 today).
18. **Empty states** come in four styles; the Flipboard's is brief 96's. Leave the Inbox's alone (George has seen
    it many times); make Search's and the one-line ones consistent with each other only if it is plainly a defect.

## Ownership
`Views/Tabs/ScreenMenu.swift`, `Views/MacChrome/*`, `SettingsView.swift`, `Views/Settings/*` and `Settings/Mac/*`
except `ICloudCheck.swift`, `ICloudSettingsGroups.swift` and the sync rows of the Mac's iCloud section (95) and
the one "Quick add guide" row brief 98 adds to General; `Views/Account/WhatsNewPopout.swift` and the feedback
sheet; `ListChrome.swift`, `TaskListView.swift` and the list screens for items 7, 11 and 12; the Mac board's
header lines in `Views/Upcoming/` (not its swipe "Pick Date" or `TaskRescheduling.swift`: 97); `SidebarView.swift`;
`BrowseView.swift` except the "?" brief 98 adds; the design system where a fix belongs there; `SpacingTests`, the
tests of what you change, a UI test file of your own. Not yours: `Views/Flipboard/*` (96), `Views/Popouts/*` (97),
`Support/SyncStatusViews.swift` (95), companions and the list's bottom inset under the "+" (100), the entries in
`WhatsNew.swift`, `scripts/`, `dev/`, `CHANGELOG.md`.

## Done
The table of items: what was measured before, what it is now, the commit, the crops (in the shared notes folder,
`99-sweep-polish/`). The "…" table. Contact sheets of the Mac's screens and Settings sections and the iPhone's main
screens after your changes. All three suites green, your UI test on a fresh simulator. The branch; changelog
lines only for what a person would notice; anything that turned out to be taste, for George, with your suggestion.
