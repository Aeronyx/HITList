# Brief 86: Settings you can find things in (session `settings-tidy`, effort xhigh)

George, 2026-11-11, on 0.9.2:

> Also, please clean up the settings menu a bit; it's become a jumbled mess and takes far too long to scroll
> through, plus many options are weirdly grouped and Appearance/Themes should be much closer to the top. Please
> also add a mini sprite of each creature on each theme! They don't have to be fully visible: some could be poking
> out from behind their theme cards/hues or some could be sitting on top of their theme colors, etc.

Read `dev/briefs/COMMON.md` (Round 19 block first), `dev/briefs/ROUND-19.md`, `dev/briefs/HIG-NOTES.md`,
`HITList/Support/DesignSystem/README.md` (custom controls are mandatory; George calls default SwiftUI controls "AI
slop"), then Settings as it is: `HITList/Views/SettingsView.swift` (`allGroups`: the iPhone sheet is one column of
eleven groups), `HITList/Views/Settings/*` and `Settings/Mac/*`, `HITList/Views/Delight/DelightSettingsSection.swift`.

## What the supervisor found
The iPhone sheet, top to bottom: Account (name, picture, iCloud), Signing out, Your data (export, delete all from
iCloud, delete profile), General, iCloud Sync, Reset local cache, Export and import, Backups, Reminders (with
Authorization, Open system settings, Scheduled, Send a test notification), Extras (completion sound, your own
sound, haptics, sync bolt, holiday touches, rare surprises, companions, weather), Appearance (**ninth**), Claude,
About. Export appears twice. Status rows that only matter when something is wrong sit among the choices. The Mac
page has nine sections with Appearance sixth.

## The rules
1. **One short first screen.** On iPhone and iPad, Settings opens on a screen that fits an iPhone 17 without
   scrolling, or nearly: the profile (picture and name; a tap opens Account), then **Appearance: the eight themes,
   right there, second thing on the screen**, then a short list of pages, each a row with its symbol, name and one
   line saying what is inside. A page opens inside the sheet (pushed, with a back control in the sheet's bar, the
   edge swipe, the design system's motion; never a second sheet) and holds one topic.
2. **Everything has one home**, and the home is where a person would look. Audit every row first (a table: the
   row, where it is, where it goes, why), then build. The supervisor's grouping, to improve on where your audit
   disagrees:
   - **Account**: name, picture, the iCloud account's state, signing out, delete profile.
   - **Appearance** (on the first screen): the themes; Reduce effects with them. On the Mac, its own section,
     second.
   - **General**: start screen, week starts on, the app icon's count, calendar events, keyboard shortcuts (Mac).
   - **Reminders**: notify at due time, default reminder, morning summary; then a small "If reminders don't
     arrive" group at the foot with the permission's state, the system's settings, how many are scheduled and the
     test notification.
   - **Extras**, in three small groups: completing a task (sound, your own sound, haptics); companions
     (Companions, Weather with Apple's attribution); effects (sync bolt, holiday touches, rare surprises).
   - **iCloud & data**: sync state and last change, the sync log, backups, export and import (once); then, last
     and apart, the two that destroy something: reset local cache, delete all data from iCloud.
   - **Claude**: as it is, shown when it is shown today.
   - **About**: version and What's New, privacy policy, show tips again, feedback.
3. **The Mac has the same homes under the same names**, in the same order (Account, Appearance, General,
   Reminders, Extras, iCloud & data or the two it has today if one page would be too long, Claude, About). The
   stored section ids (`MacSettingsSection` raw values) stay valid: keep the raw values you keep, and a stored one
   that no longer exists falls back to General, as `remembered` does. Captions stay 24 characters or fewer.
4. **Rows read at a glance.** A title, and a second line only where the title cannot carry it. A footer is two
   lines at most or it is a row's subtitle. A status that only matters when something is wrong shows only then, or
   lives in its page's last group. No option is removed and no stored key is renamed: every preference keeps its
   key and its meaning.
5. **Everything that leads into Settings still arrives**: the Mac's `SettingsRouter`, the links from What's New,
   the Weather row's "Open system settings", the sync mark's way to iCloud, the tips. List them and test them.
6. **A companion on each theme.** On each theme's swatch (the iPhone grid and the Mac's larger swatches) the
   theme's own companion appears in miniature, in that theme's inks: `CompanionCast.character(forTheme:)`, drawn
   with `CompanionSprite(character:pose:inks:pixel:)` and `CompanionInks(palette:)` at **1 point a pixel** (half
   the size it has in the app), still, hidden from VoiceOver, never taking the tap that picks the theme. Each sits
   its own way, as George says: one sitting on the swatch's card with its legs over the edge, one lying along its
   top, one peeking from behind it with only its ears and eyes showing, one asleep on the accent dot. Design the
   swatch so there is room (it may grow; two rows of four stay). A placement table keyed by character id, with a
   sensible default for a character it does not know (brief 85 is drawing two new ones tonight; the supervisor
   tunes their entries after the merge). A theme whose companion is not drawn yet (it would show Nod) shows none,
   so the grid never has four Nods. Extras → Companions off hides them all.
7. **George's eye.** He checks spacing to the pixel: shared left edges, a symbol 4 pt from its text, one section
   header style, one row height per kind of row, the same paddings on every page. Screenshot every page on an
   iPhone 17 and on the Debug Mac app and look at each as he would: a name shown twice, two controls that look
   alike, a control nobody asked for.

## Items (one commit each)
1. **The audit table** (in your report, not a file) and the page structure on iPhone: the first screen, pushed
   pages inside `HITSheetChrome`, the back control, the motion.
2. **Each page**, regrouped (one commit per page is fine).
3. **The Mac**: the same homes, Appearance second.
4. **The swatches with their companions**, iPhone and Mac.
5. **The ways in** (rule 5), tested; the Settings UI tests and the screenshot tour updated for the new paths.

## Ownership
`HITList/Views/SettingsView.swift`, `HITList/Views/Settings/*` and `Settings/Mac/*` (not `WhatsNew.swift`'s
entries), `HITList/Views/Delight/DelightSettingsSection.swift`, additions to `HITList/Support/DesignSystem/*` that
a pushed page needs (add; do not change how an existing component looks elsewhere), a new
`HITList/Views/Settings/ThemeCompanion.swift` (the miniature and its table), `HITListTests/SettingsTests.swift`
(not the What's New pin), `MacSettingsTests`, the lines of existing UI tests that walk through Settings
(`ScreenTourUITests` and any other: list them in the report), a UI test file of your own.
Not yours: `HITList/Services/Weather/*` (brief 83 changes the Weather row's words in
`Services/Weather/WeatherSettingsText.swift` and its default; you move the row and keep it wired to
`CompanionWeather.shared` exactly as it is), `HITList/Support/Companions/*` and `Views/Companions/*` (84 and 85:
read `CompanionCast`, `CompanionSprite`, `CompanionInks`; change nothing there), `Support/Preferences.swift`'s
existing keys, core, the models, `project.yml` beyond what `xcodegen generate` needs, `dev/ROADMAP.md`,
`CHANGELOG.md`, `WhatsNew.swift`.

## Done
The audit table. Before and after, iPhone 17 and Mac: the first screen and every page, and the height of the
iPhone's content before (one column) and after (the first screen, the longest page). The swatches with their
companions on both platforms at real size and enlarged. The ways in, each with its test. All three suites green,
the UI tests that touch Settings on a fresh simulator. Decisions George may want to reverse, each in one line.
