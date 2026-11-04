# Brief 40: profile top-left, Flipboard rightmost (branch `profile-chrome`, effort High)

Read `briefs/COMMON.md` first. Six sessions run at the same time; see COMMON's "Round 10 ownership". Session 42 is
hardening `ProfileStore` and the Account screen at the same time: use `ProfileStore`'s existing API and
`ProfileBadge` as they are; report anything you need changed there.

George's words, on 0.5.0 (15), 2026-11-04:

> I was wrong; please swap the positions of Flipboard and Upcoming again so Flipboard is rightmost.

> Profile/Account should be at the top left of the desktop app, showing only their name/profile pic with a
> dropdown to access account settings there if they want to. In Mobile, it should be at the top left of the Browse
> page.

## Items (one commit each, failing test first where there is logic)

1. **Tabs** (`MobileTabBar.swift`): Inbox · Today · Upcoming · Flipboard. Update `MobileChromeTests`.
2. **Mac top-left** (`SidebarView.swift`, new `Views/Account/ProfileMenu.swift`): at the top of the sidebar, above
   Inbox/Today, the avatar (initials fallback) and the name, compact (Todoist's account button is the model: avatar
   24 pt, name in `HITType` sidebar size, a small chevron), opening a dropdown (custom design-system menu, not the
   default "AI slop" look): "Account settings…" (opens the Mac Settings page straight at Account through
   `SettingsRouter`), "Settings…", a divider, the iCloud state line (read-only, same words as Settings → Account).
   With no name set it shows the placeholder avatar and "Add your name". It sits in the sidebar's own top area,
   not the window toolbar, and must not fight the traffic lights or the sidebar toggle.
3. **iPhone Browse top-left** (`BrowseView.swift`): the profile moves from the row inside the list to the top-left
   of Browse, beside the Back chevron (a small avatar + name, or avatar only if the name does not fit), tapping it
   opens Settings with Account at the top (or straight at Account if `SettingsView` can scroll there in a few
   lines). Remove the list row.
4. **iPad** (sidebar layout): same as the Mac top-left.

## Ownership
`Views/Tabs/MobileTabBar.swift`, `BrowseView.swift`, `SidebarView.swift`, new `Views/Account/ProfileMenu.swift`,
`Views/Settings/Mac/SettingsRouter.swift` (opening at a section only), `SettingsPreferences.swift` (only if the tab
order is stored there); tests `MobileChromeTests`, new `ProfileMenuTests`; `project.yml` only to add files; ROADMAP
row "Profile top-left, Flipboard rightmost (brief 40)". Not yours: `MobileShell.swift`, `ContentView.swift` (45),
`AccountSettingsSection.swift`, `ProfileStore.swift` (42), `MacSettingsSection.swift` list (43 adds a Claude entry).

## Done
All three suites green; iPhone simulator screenshots of the tab bar and Browse's top-left; an offscreen PNG of the Mac
sidebar top with and without a name, and the open menu; iPad simulator screenshot of the sidebar top.
