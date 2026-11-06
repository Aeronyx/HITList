# Brief 52: first-run tips, Spotlight, Mac Settings polish, cleanup (branch `tips-spotlight-cleanup`, effort High)

Read `briefs/COMMON.md` (Round 11 block) and `briefs/HIG-NOTES.md` first. Five sessions run at the same time.

From George on 2026-11-05 ("definitely read & brush up on the tips and tricks found on developer.apple.com/design";
"Clean up any old files as needed") and the HIG pages on onboarding, Siri/iCloud search and macOS settings. Friends
are about to start using the app.

## Items (one commit each, failing test first where there is logic)
1. **Context tips for new people** (TipKit; new `Views/Tips/*`): four to six short tips, each shown once, at the
   moment it helps: quick-add syntax on the open card ("Try ‘Call mom tomorrow 5pm p1 #Home’"), "Tap a highlight, or
   Backspace right after it, to keep the words as text", the magnifying glass for Browse, Flipboard, the board's day
   Add task on the Mac. Dark-slate styling consistent with the design system. Settings → About → "Show tips again".
   `Tips.configure` once at launch (one line in `HITListApp.swift`). Where a tip attaches inside a file another session
   owns, add a `.hitTip(...)` modifier only if that file is unowned, otherwise report the one-line attach point.
2. **Spotlight** (Services/Intents, new `Services/Spotlight/*`): open, top-level tasks searchable in Spotlight
   (`IndexedEntity` on `TaskEntity`, or `CSSearchableIndex`), updated in batches after saves and imports, removed on
   completion/deletion, cleared on an account switch (one line in `AccountSwitch`), never in Debug side-store runs;
   tapping a result opens the task. Respect the Claude-style privacy idea? No: Spotlight is the person's own device.
3. **Mac Settings, HIG**: the Settings window/page title names the visible pane; Settings reopens on the last pane;
   ⌘, opens it from the app menu (check what exists; `MacSettingsPage.swift`, `SettingsRouter.swift`).
4. **Cleanup**: find dead code and stale files (Swift types and files nothing references, unused assets and fonts,
   stale scripts, stale docs) with evidence (grep/compiler); remove them with `git rm` in one commit per kind, listing
   each in the report. Keep `BackupService.swift`, `Keychain.swift` and `server/` (George's optional home-server path;
   ask George in your report whether they should go). Do not touch files another session owns this round.

## Ownership
New `Views/Tips/*`, `Services/Spotlight/*`, `Services/Intents/*`, `HITListApp.swift` (one line), `AccountSwitch.swift`
(one line), `Views/Settings/AboutSettingsGroup.swift`, `MacAboutSection.swift` (Show tips again),
`Views/Settings/Mac/MacSettingsPage.swift`, `SettingsRouter.swift`; dead files only where no session owns them; tests
new `TipsTests`, `SpotlightTests`; `project.yml` only to add or remove files; ROADMAP row "Tips, Spotlight, Mac
Settings, cleanup (brief 52)".

## Done
All three suites green; simulator screenshots of two tips and a Spotlight result for a task; a capture of the Mac
Settings window title (`scripts/window-shot.sh`); the cleanup list.
