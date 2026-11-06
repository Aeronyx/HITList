# Round 9 queue (George's feedback on 0.4.1 (14), 2026-11-04)

The supervisor's first job: turn this into briefs 34–38, commit them, start the sessions (§4 of
`SUPERVISOR.md`). George's words are verbatim; the notes under each are Fable's reading of the code and
the questions to settle before a session starts. Four screenshots came with the feedback: two of the task
editor at its medium height (the second has more room above the Confirm pill, which George prefers), the
quick-add card with "test 2 [p1] [tom] [4]" highlighted as three boxes and chips Tomorrow · P1 · 4:00 AM,
and Todoist's Upcoming board on the Mac (Overdue column with a Reschedule link, then one column per day
with cards and an "Add task" row, month picker and Today arrows above).

## 1. Accounts, privacy policy, app review

> I would indeed like my friends to have their own full accounts, which I understand requires an extra
> review; let's get on basic account/profile implementation, privacy policy, and app review right away.
> (I say "basic," but I want you to ensure the account/profile system has the same robustness and
> reliability of our cloud sync).

Settle with George in one message before writing the brief; the answers change the whole design:
- Each tester already gets their own private data: CloudKit's private database is per Apple ID, and the
  TestFlight build syncs each friend's tasks under their own iCloud account with no code change. So what
  does an "account" add? The likely answer is a profile (display name, avatar, maybe a handle) and the
  App Store's expectations for an app with accounts (sign-in, sign-out, account deletion). Propose:
  identity = the iCloud account (`CKContainer.fetchUserRecordID` + `SyncEnvironment`), profile = a
  `Profile` record in the private database (new schema version, additive), Settings → Account screen
  with name/avatar, "Signed in as" from `userRecordID`, and account deletion = delete the profile record
  and offer the existing data reset. Sign in with Apple only if George wants a login separate from
  iCloud (it needs nothing server-side either, but it is a second identity to reconcile).
- "Same robustness as sync" = the profile write path goes through `SyncLog`/`SyncWatchdog` like every
  other record, with the environment line in Settings → iCloud showing the account state.
- Privacy policy: needs a public URL in App Store Connect (App Information and the TestFlight Test
  Information). Draft `PRIVACY.md` (data stays in the user's iCloud; no servers of ours; no analytics;
  notifications local; what diagnostics "Copy diagnostics" contains) and ask George where to host it
  (GitHub Pages on the repo, or trammells.com).
- "App review" here means Beta App Review for external TestFlight testers: Test Information (what to
  test, feedback email, privacy URL), "Sign-in required" only if the build has a login, demo account
  if so. List the App Store Connect click path for George; a session cannot do it.
- Effort xhigh; data-model change ⇒ schema deploy before the release; owns `Models.swift`,
  `SchemaVersions.swift`, new `Views/Settings/AccountSettingsSection.swift`, new `Services/ProfileStore.swift`,
  `SyncLog` categories, `PRIVACY.md`.

## 2. Tab bar and Browse

> Replace the Browse tab on the home menu bar with the Flipboard, putting the Browse tab/button instead
> where the three dot menu is in the top right, then swap the position of Flipboard and Upcoming (so
> Upcoming is furthest right), and then within the Browse tab, leave the in-line Settings button where
> it is at the bottom of the list but replace where the Browse button now would be within Browse in the
> top right to be the Settings button instead (essentially making it a two tap process on the top right
> button to get to Settings, with the first tap bringing you to the Browse page and looking like a Search
> icon, and the second looking like a settings gear or wrench, whichever fits the app's vibe better).
> Remove the in-line Flipboard button from the Browse page so the last two buttons are just Completed and
> Settings for now.

Result: tabs Inbox · Today · Flipboard · Upcoming; the top-right control on every tab is a search icon
that opens Browse (the "…" menu's other items, Settings… and the version, move: Settings is reached from
Browse, the version lives in Settings → About already); on Browse the top-right control is a gear that
opens Settings; Browse's list ends with Completed and Settings. Files: `Views/Tabs/MobileShell.swift`,
`MobileTabBar.swift`, `BrowseView.swift`, `ScreenMenu.swift` (`screenChrome`), `Preferences.startTab`
(Flipboard becomes a valid start tab), `MobileChromeTests`. Mac unchanged. Effort High.

## 3. Editor space, bigger Confirm, no keyboard confirm

> Give the "Edit task" pane some more screen space (a pair of screenshots attached to show the
> difference), increase the size of the "Confirm task" button both on the edit screen and the "Add task"
> screen, remove the "Created at ..." line and breakline, and remove the checkmark/confirm button on the
> iOS keyboard, only allow task confirmation via the "Confirm task" button.

The sheet's medium detent should sit higher (or open at a taller custom detent, e.g. `.fraction(0.72)`)
so the Sub-tasks card and the Confirm pill have air; the Confirm pill grows on both the editor and the
quick-add card (same component, one size constant in `QuickAddPopout.footer` / the editor footer); the
"Created …" line and the divider above the footer go (keep the date in the "…" menu); the title field's
`submitLabel(.done)`/Return no longer saves (Return does nothing in the title; sub-task lines keep Return
= next line). Files: `TaskPopout.swift`, `Editor/*`, `QuickAddPopout.swift` (footer + title submit),
`TokenHighlightField.swift` (`onSubmit`/`submitLabel`), `PopoutHost.swift` (sheet detents), `PopoutTests`.
Effort High. Ask nothing; the screenshots are the spec.

## 4. Highlight merging and override

> Quickadd highlights should fill the space between words if they're next to each other and have the
> same color highlight/category; for example, in the third attached screenshot, "[tom] [4]" should be
> "[tom 4]" visually. Also, if a later quickadd highlight is to overwrite an earlier one, let it, but
> clicking/tapping on it to remove it should then restore the first quickadd highlight (e.g. "jan 6
> zach fox [in a month]" reverts to "[jan 6] zach fox in a month").

Two parts. Visual merge: adjacent tokens of the same kind separated only by spaces draw as one box
(`TokenHighlightField.areas` joins rects on the same line when the gap is whitespace and the kinds match;
tapping the joined box disables both tokens). Override: the parser already lets a later date phrase win;
make the loser a `QuickAddToken` with a `superseded` flag (no highlight, no effect), and `disable` of the
winner (`QuickAddParser+Disabled`) re-parses so the earlier phrase applies again. Tests in HITListCore
for the parse and in `PopoutTests` for the areas. Files: `QuickAddParser.swift`, `+Disabled.swift`,
`TokenHighlightField.swift`, `QuickAddDraft.swift` (`disable`). Effort High.

## 5. Mac Upcoming as a board

> Can the Upcoming tab of the desktop app look like the fourth attached screenshot instead of a copy of
> the mobile app Upcoming tab? Side scrolling in this tab allows for much easier views of upcoming days
> (only for 7 days ahead).

Mac (and iPad regular width) only: a horizontally scrolling board, one column per day for today plus
six days, an Overdue column first with its count and a Reschedule action (the existing
`TaskRescheduling`), cards (`Theme.surface`, title, description first line, date/time, Group) that drag
between columns to reschedule, an "Add task" row at the foot of each column opening the inline add with
that day as context, a month label and Today/arrows above (arrows move a day; "only for 7 days ahead"
means the window is seven columns, not that it cannot start later). iPhone keeps its list. Files:
`Views/Upcoming/UpcomingView.swift` (platform split), new `Views/Upcoming/UpcomingBoard.swift`,
`UpcomingSchedule.swift`, `TaskRescheduling.swift`, `UpcomingScheduleTests`. Effort xhigh (drag and
drop on the Mac is fiddly; the session cannot screenshot the Mac, so it must render the board offscreen in
a test and list what George should look at).

## Parallelism

1 (model + Settings), 2 (iPhone shell), 3 (editor + card footer), 4 (parser + highlight field) and 5 (Mac
Upcoming) are disjoint by file except: 3 and 4 both touch `TokenHighlightField.swift` (3: submit label;
4: areas) and `QuickAddPopout.swift` (3: footer; 4: nothing if `disable` stays in `QuickAddDraft`). Give
3 the field's submit lines and 4 the areas function, say so in both briefs. Run 2, 3, 4 and 5 together;
start 1 once George has answered the questions above (it needs the schema deploy before the next release,
so it should also be the last merged). Next release: 0.5.0 (15) if accounts land, else 0.4.2.
