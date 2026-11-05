# Brief 49: Extras, Claude off by default, sidebar spacing, Discard inside the card (branch `extras-claude-polish`, effort High)

Read `briefs/COMMON.md` (Round 11 block) and `briefs/HIG-NOTES.md` first. Five sessions run at the same time.

George's words, 2026-11-05:

> Make the Claude integration disabled entirely by default; only offer the privacy option when the user
> intentionally enables the Claude integration within Settings.

> Put slightly more vertical space between the profile in the top left and the first menu tab (the Inbox).

> Change "Delight" to "Extras".

> Have the "Discard?" popup appear contained within the "Add task" card on the desktop's Upcoming page instead of
> popping out above it.

## Items (one commit each, failing test first where there is logic)
1. **Claude, off and quiet by default** (`ClaudeSettingsSection.swift`, `Services/Claude/*`, the helper's messages):
   Settings → Claude shows one switch, "Claude integration", off, with one plain sentence of what it does. Only when
   it is on do the privacy choice (all but `@private` / only `@claude`, label names), the Mac setup snippets, Test
   connection and Copy for Claude appear. Turning it on shows a short confirmation that says exactly what Claude will
   be able to see and do (HIG: generative AI, people stay in control). Off means: no local port, the helper answers
   "Claude integration is off in HITList", "Copy for Claude" appears nowhere (menus, share sheets, Browse). Someone who
   already turned it on keeps it on. Tests for the gating.
2. **Claude's completions get the Undo toast** (`PopoutController.swift`): listen for `.claudeDidCompleteTask` (brief
   43) and show the same toast a completion in the app shows, so a Claude completion is one tap from undone.
3. **"Delight" → "Extras"** in every user-facing string: the Settings section on iPhone and the Mac page's section
   list, headers, footers, accessibility labels, the README of the design system if it names the section. Keep the
   type and file names (`DelightSettingsSection` etc.) so sibling sessions' one-line additions merge; past What's New
   entries stay as written.
4. **Sidebar spacing** (`SidebarView.swift` / `Views/Account/ProfileMenu.swift`): slightly more vertical space between
   the profile button and Inbox on the Mac and iPad (about 8 pt more; judge it in a capture of your Debug Mac window
   with `scripts/window-shot.sh`, COMMON). Keep the profile's left edge on the rows' icon column.
5. **Discard inside the card** (`CompactQuickAddCard.swift`, `QuickAddPopout.swift` compact style's Discard only):
   on the Mac (and iPad) Upcoming board, the "Discard this task?" question appears inside the add card itself (an
   inline row at the card's foot with Keep editing / Discard, the card growing to fit), not as a bubble above it. Esc
   twice and × twice still discard. Do the same for the Mac lists' inline "Add task" row (`InlineAddRow` in
   `QuickAddEntry.swift`), whose × still closes without asking (open item from round 10).

## Ownership
`Views/Settings/ClaudeSettingsSection.swift`, `Services/Claude/*`, the helper target's sources (messages only),
`docs/connect-claude.md`; `Views/Popouts/PopoutController.swift`; `Views/Delight/DelightSettingsSection.swift` and
`Views/Settings/Mac/MacSettingsSection.swift` (strings only; session 50 adds one row line to the former), any other file
only for a "Delight" string; `SidebarView.swift`, `Views/Account/ProfileMenu.swift` (spacing); `CompactQuickAddCard.swift`,
`QuickAddPopout.swift` (compact style's Discard only), `QuickAddEntry.swift` (`InlineAddRow` only); tests new
`ClaudeGatingTests`, `CompactQuickAddTests`; ROADMAP row "Extras, Claude off by default, Discard in the card (brief 49)".
Not yours: `TokenHighlightField.swift` (47), the Reminder chip region of `QuickAddPopout` (48), `PopoutHost.swift`,
`MobileTabBar.swift` (50), `BrowseView.swift` (51).

## Done
All three suites green; iPhone simulator screenshots of Settings → Claude off and on, and Settings → Extras; captures
of your Debug Mac window: the sidebar top, the board card asking Discard inside itself.
