# Brief 35: Flipboard tab, Browse behind a search icon, Settings behind a gear (branch `tabs-browse`, effort High)

Read `briefs/COMMON.md` first. Session 36 (task editor and quick-add card footer) runs at the same time;
sessions 34, 37 and 38 may already be merged into master when you start. iPhone only: the Mac and iPad keep the
sidebar and their toolbar unchanged.

George's words, from the 0.4.1 (14) feedback on 2026-11-04:

> Replace the Browse tab on the home menu bar with the Flipboard, putting the Browse tab/button instead
> where the three dot menu is in the top right, then swap the position of Flipboard and Upcoming (so
> Upcoming is furthest right), and then within the Browse tab, leave the in-line Settings button where
> it is at the bottom of the list but replace where the Browse button now would be within Browse in the
> top right to be the Settings button instead (essentially making it a two tap process on the top right
> button to get to Settings, with the first tap bringing you to the Browse page and looking like a Search
> icon, and the second looking like a settings gear or wrench, whichever fits the app's vibe better).
> Remove the in-line Flipboard button from the Browse page so the last two buttons are just Completed and
> Settings for now.

## The result

- Tab bar, left to right: **Inbox · Today · Flipboard · Upcoming**, the "+" oval above it as today.
- On Inbox, Today, Flipboard and Upcoming the top-right control that was the "…" is a **magnifying glass**
  (`magnifyingglass`, same size and glass treatment as the control it replaces) that pushes **Browse** onto the
  current tab's navigation stack (Back returns to the tab).
- On Browse the top-right control is a **gear** (`gearshape`; it fits the slate look better than a wrench) that
  opens Settings the way the "…" menu's Settings… does today (a sheet on iPhone).
- Browse's list keeps its rows and the in-line Settings row at the bottom, and loses the Flipboard row: the
  last two rows are Completed and Settings.
- The "…" menu's per-screen items (Inbox review, Flipboard actions, anything a screen passes as `Items` to
  `screenChrome`) do not disappear: on iPhone they move into that screen's own view-options control (the other
  top-right button), under a divider. Settings… and the version leave the iPhone menu (Settings is reached
  through Browse; the version is in Settings → About). The small `SyncBolt` stays where it is.

## Items (one commit each, failing test first where there is logic)

1. **Tabs** (`MobileTabBar.swift`, `MobileShell.swift`): `MobileTab` becomes `inbox, today, flipboard,
   upcoming` (keep a `browse` destination for navigation, not as a tab); Flipboard's tab icon and title match
   its sidebar entry. Tests in `MobileChromeTests`: order, titles, icons.
2. **Start tab** (`SettingsPreferences.swift` `startTabValue`, `GeneralSettingsSection.swift` picker): Flipboard
   is a valid start screen; a stored `"browse"` (someone who chose Browse as their start screen) falls back to
   Today. Test-first.
3. **Search icon → Browse** (`ScreenMenu.swift`'s `screenChrome`, iPhone branch only; Mac branch untouched):
   the magnifying glass pushes Browse; the screen's items join its view-options menu. Check every caller of
   `screenChrome` on the iPhone (Inbox, Today, Upcoming, Flipboard, Group and filter screens pushed from Browse:
   decide whether those show the search icon too; a screen already inside Browse should not push a second
   Browse, so show the gear or nothing there and say what you chose).
4. **Browse** (`BrowseView.swift`): top-right gear opens Settings; remove the Flipboard row; Completed then
   Settings last. Accessibility labels "Browse" and "Settings".
5. **Tidy**: anything that navigated to the Browse tab or the Flipboard row (deep links, `MobileShell`'s tab
   switching, notifications that open a tab, `PopoutHost` assumptions about the tab bar's height or count)
   still works; the "+" oval and the Undo toast sit where they did.

6. **Who is signed in, on Browse** (`BrowseView.swift`): session 34 (merged) built `ProfileBadge` (avatar and
   name) in `Views/Settings/AccountSettingsSection.swift` and left it unplaced. Put it at the top of Browse as a
   quiet header row that opens Settings → Account (or Settings, if a direct route to Account is more than a few
   lines); with no name set it reads "Add your name". Use it as it is; if it needs a change, report it.

Master since the brief was written: briefs 34, 37 and 38 are merged; `SyncBolt.look` and
`SyncIndicatorDot.color` take an `everSignedIn` argument (grey for someone who never used iCloud) and one line of
`MobileChromeTests` passes `everSignedIn: true`.

## Ownership

`HITList/Views/Tabs/MobileShell.swift`, `MobileTabBar.swift`, `BrowseView.swift`, `ScreenMenu.swift` (iPhone
branch); `Views/Settings/SettingsPreferences.swift` (start tab only), `GeneralSettingsSection.swift` (start
picker only); the iPhone `screenChrome` call sites' `Items` (one-line changes in `InboxView`, `TaskListView`,
`UpcomingView`, `FlipboardView` if an item has to move; nothing else in those files: session 38 owns
`Views/Upcoming/*`, so keep any `UpcomingView` edit to that call site); tests `MobileChromeTests`; `project.yml`
only to add files; ROADMAP row "Flipboard tab, Browse and Settings behind the top-right control (brief 35)".

Not yours: `SettingsView.swift` and new Account files (34), `PopoutHost.swift`, `QuickAddPopout.swift`,
`TaskPopout.swift` (36), anything Mac-only.

## Done

All three suites green; iPhone simulator screenshots: the tab bar with Flipboard third and Upcoming last; the
magnifying glass on each tab; Browse pushed with the gear; Settings opened from the gear; Browse ending with
Completed and Settings; a screen's former "…" items inside its view-options menu; Flipboard chosen as the start
screen and the app relaunched onto it.
