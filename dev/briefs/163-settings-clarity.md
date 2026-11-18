# 163: Settings a friend can read: every page, the Calendar page first (code)

George, 2026-11-18: "I've also noticed some confusion with the settings menu; some of the pages are not very
user-friendly (such as the Calendar page) and some of the tooltips are really hard to read/need to be more
concise … I want to be really comfortable sending this out to people, but we're still not quite there." External
testers who have never met George now use the app: Settings must explain itself to them.

**Yours**: `HITList/Views/SettingsView.swift`, `HITList/Views/Settings/` (and `Mac/`), `HITList/Views/Calendar/
CalendarSettingsRows.swift`, `HITList/Views/Delight/DelightSettingsSection.swift`, the UI tests that read Settings'
words (`SettingsTidyUITests`, `CalendarEventsUITests`, `ProfileMenuUITests`: change a label there only when you
changed it in the app). **Not yours, not a character**: `SyncEngineSettings.swift`, `ICloudCheck.swift`,
`SyncLogView.swift`, `WhatsNew.swift`, `Views/Tips/` (agent 162), `Views/Account/BetaFeedback.swift` (166). In
`ICloudSettingsGroups.swift` you may change layout and words only: no action, condition, preference or the
seven-tap row (`SevenTaps`); the sync words there were settled over many rounds, so change one only where a
friend would stumble, and list each change.

1. **See it first**: a picture of every Settings page and sub-page, on an iPhone simulator and on the Mac, before
   any change (your notes folder, `before/`). Read each as someone who installed the app yesterday. Write down, per
   page, what would stop them: a row whose effect they cannot guess, a paragraph nobody reads, a control that does
   nothing visible, a state not shown (allowed or not, on or off, which calendar), words from inside the project,
   two rows for one idea, an order with no reason.
2. **The Calendar page first** (George named it). It should read in ten seconds: what it does ("Show your
   calendar's events in Today"), one switch, the state of the permission in plain words with the one tap that
   fixes it when it is refused, which calendars (only when on), and Add to Calendar's own row if it belongs here.
   Nothing asks for permission until the person turns something on (the existing rule).
3. **Then every other page, worst first**, by these rules: a row's title is at most three or four words and names
   the thing; a subtitle only where the title cannot carry it, one line; a group's footer is one sentence (two at
   most) and never explains the machinery; a disabled row says why in its subtitle; a destructive row is red and
   confirms; related rows sit together, most used first; the iPhone and the Mac say the same thing with the same
   words. Where a page is fine, leave it.
4. **Nothing is removed that works and nothing stored changes**: no preference key renamed or re-typed, no default
   changed, no feature dropped. A row that should not exist at all: list it in your report with why; do not delete
   it.
5. Layout: dark themes only, the design tokens; no text within 12 pt of a card's or the screen's edge, 8 pt beside
   a control, 6 pt between lines of different things; nothing truncated at the default size on an iPhone 16; at
   the largest ordinary Dynamic Type size rows grow, they do not clip.

Proof: pictures of every page after (`after/`, the same names as before), iPhone and Mac; the UI tests named above
and `AccessibilityAuditUITests`' Settings cases on your simulator; `HITListTests` whole on the Mac at the end
(several tests pin Settings' words: `SyncEngineStatusTests`, `SettingsTests`; a pinned word you changed on purpose
changes there too, and is listed). Your report: per page, what was wrong and what you did, in a line each; what you
left and why; every string you changed in `ICloudSettingsGroups.swift`.
