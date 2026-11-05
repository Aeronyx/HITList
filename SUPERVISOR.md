# HITList supervisor handbook

For the Claude Code session that runs HITList rounds in this folder: reads George's feedback, writes
briefs, starts Opus 5.5 sessions in worktrees, merges and tests their branches, checks the result in the
iPhone simulator, writes the release notes and hands George the release command. Fable 5.1 did this for
rounds 1–8 (2026-10-26 to 2026-11-04); from round 9 an Opus 5.5 session does it. Read this file first,
then `briefs/COMMON.md` (the facts every delegated session reads), then the queue in `briefs/ROUND-9.md`.
The memory folder under `~/.claude/projects/-Users-gtrammell-Desktop-HITList/memory/` is loaded into every
session in this folder and holds the same rules in shorter form; keep both in step when something changes.

## 1. The app and the person

HITList ("Human-in-the-List") is George Trammell's personal Todoist-style task app: SwiftUI, SwiftData with
CloudKit (`iCloud.com.trammells.hitlist`, private database), iOS 18+ and macOS 15+, dark slate theme only
(George never uses light mode), Inter typeface through `HITType` roles. `HITListCore` is a pure Swift
package (filter language, quick-add parser, dates, recurrence, ordering, snapshot JSON); `HITListTests` is
the app test bundle (in-memory container, hosted in the app, runs on the iPhone 17 simulator and the Mac).
George uses the app every day on an iPhone 16 and a Mac, both on TestFlight, and is about to invite
friends as external TestFlight testers. `ROADMAP.md` is the plan and the log of every round; `DESIGN.md`
is the original design; `CHANGELOG.md` has a section per version; `HITList/Support/DesignSystem/README.md`
is the component guide (custom button, toggle, chip and field styles are mandatory; George calls default
SwiftUI controls "AI slop").

How George works with you:
- They read instructions only in chat. Every command, click path and checklist goes in your message,
  in full, with fenced `bash` blocks; files are records, not where George reads what to do.
- They give detailed UI feedback after each TestFlight build, with screenshots, and scrutinise spacing to
  the pixel (checkbox centred on the title line, icon 4 pt from its text, shared left edges). Expect
  "the kerning is slightly too much, by like a pixel" and treat it as a real item.
- Always state the effort level you chose for each session (High, xhigh, Max) and why.
- They run releases themselves. You prepare everything and hand over the command. Version numbers must be
  right first time (see §6).
- Ask before anything hard to reverse. Decisions they have already made are listed in §7; do not re-ask.
- They are on a weekly subscription limit. Prefer one careful pass over repeated attempts; read a
  session's report once, in full, and keep your own simulator checks to what the sessions could not do.

## 2. Environment (each of these cost hours to learn)

- Every `xcodebuild`, `swift`, `xcrun` and `xcodegen` command needs
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (xcode-select points at the command-line
  tools). Xcode 27.1, macOS 26.7.1.
- The Xcode project is generated from `project.yml` with XcodeGen: edit `project.yml`, run
  `DEVELOPER_DIR=… xcodegen generate`; never hand-edit the xcodeproj. The `sources` lists are whitelists:
  a new file outside them does not compile. Run `xcodegen generate` after every merge that adds files.
- Tests: `scripts/test.sh` (all three suites, about three minutes), or `scripts/test.sh core`,
  `scripts/test.sh macos`, `scripts/test.sh ios`. Counts at 0.4.1: core 229, Mac 607, iOS 602. CI
  (`.github/workflows`) runs core + Mac on `macos-26`; its red runs are usually "no runner available"
  (GitHub's macOS capacity), which `gh run rerun <id>` fixes. The runner's Xcode is older than local.
- Simulator: iPhone 17, UDID `03F99117-3466-4810-A711-AF52514F6514`. Build with
  `xcodebuild build -project HITList.xcodeproj -scheme HITList -configuration Debug -destination
  'platform=iOS Simulator,id=03F99117-3466-4810-A711-AF52514F6514' -derivedDataPath build.noindex/sim
  -allowProvisioningUpdates -quiet` (about two minutes; run it in the background), then launch
  `/Users/gtrammell/Desktop/HITList/build.noindex/sim/Build/Products/Debug-iphonesimulator/HITList.app`
  (bundle id `com.trammells.hitlist`) with the iOS Simulator tool. Its screenshots lag one or two calls
  behind the screen: take two, trust the second. Typing lands before SwiftUI moves focus, so tap the field
  you mean, take a screenshot (as a delay), then type. The simulator's Debug store is throwaway test data.
- The Mac app cannot be screenshotted by any session. Mac-only looks need George's eyes: list them.
- Logs: `/usr/bin/log show --info --last 5m --predicate 'subsystem == "com.trammells.hitlist"'` (plain
  `log` is a zsh builtin). Categories: sync, storage, dedupe, delight.
- Builds live in `build.noindex/`; Xcode's DerivedData in `~/Library/Developer/Xcode/DerivedData.noindex`.
- George's real Mac app runs from `/Applications/HITList.app`; `pgrep -x HITList` shows it. Never quit
  it, never open its store (`~/Library/Group Containers/UC8N98H3RT.com.trammells.hitlist/HITList.store`).
  Debug builds use their own `HITList-Development.store` (CloudKit Development environment); TestFlight
  builds use Production.
- GitHub: private repo `github.com/Aeronyx/HITList`, default branch `master`, `gh` logged in as Aeronyx.
  Commits end with `Co-Authored-By: <model name> <noreply@anthropic.com>`.

## 3. Rules that must never break

- Production CloudKit schema is additive only, forever: never rename, delete or retype a field; new
  attributes optional or defaulted; new relationships optional; no `@Attribute(.unique)`. Every model
  change bumps `HITListSchemaV<n>` with a lightweight stage (rules in `HITList/Models/SchemaVersions.swift`'s
  header; V3 added `TaskItem.parent`/`subtasks` for 0.4.1), pins hashes in `SchemaTests`, reaches CloudKit
  Development through a Debug run (`-seedSampleData`), and must be deployed to Production in the CloudKit
  dashboard before the release that needs it (§6).
- Never add `com.apple.developer.icloud-container-development-container-identifiers` to any entitlements.
  Never open the real store under the Development environment. Never call `ModelContainer.deleteAllData()`
  or delete objects as a "reset": deletions mirror to CloudKit and wipe every device.
- Secrets: the App Store Connect key `AuthKey_RWK3KKN75R.p8` lives in `~/.appstoreconnect/private_keys/`;
  the Key ID `RWK3KKN75R` and Issuer ID `1858583d-d6ee-4039-968e-e9c2c66e3ddd` may be written, the key's
  contents never. `~/.config/hitlist/api.env` holds an API key that must never be printed or pasted (the
  $200 promotional credit behind it expires 2026-11-05 and is not used any more).
- Delegated sessions never push, open PRs, merge, switch branches, run `scripts/release.sh`, use `sudo`,
  or `rm -rf`. The supervisor pushes `master` only. George runs `scripts/release.sh` (the permission
  classifier denies it to sessions anyway).
- `BackupService.swift` and `server/` are deliberate unused design relics: leave them.

## 4. A round, step by step

1. **Read the feedback** and split it into sessions by file ownership, not by topic size: two sessions
   must never edit the same region of a file. Three parallel sessions is the sweet spot; the fourth
   waits. A session gets one coherent area (a parser, a screen, a data-model change plus its UI).
2. **Write one brief per session** in `briefs/NN-slug.md` (next number after the highest; 33 was the
   last of round 8). Each brief has: George's words quoted verbatim; numbered items ("one commit each,
   failing test first where there is logic"); an **Ownership** list of files; a **Done** section (what
   must be visible in the simulator and which suites must be green); which files it must not touch
   because a sibling owns them. Update `briefs/COMMON.md`'s "Round N ownership" block and "How sessions
   run" paragraph (build numbers, pending schema deploy). Commit the briefs to master first: worktrees
   are cut from master and must contain them.
3. **Start the sessions** with the app's session tool (`mcp__ccd_session__start_session`): `initiation`
   "user_asked", `context` "fresh", `model` "claude-opus-5-5", `effort` high (xhigh for a data-model or
   multi-screen brief), `use_worktree` true, `branch_name` the slug, `wake_when_done` true, a `background`
   of a few sentences (what the app is, that siblings run in parallel, that COMMON.md has the rules) and a
   `prompt` that says: read COMMON.md, then the brief, do it in this worktree on its branch, commit per
   item, all three suites green, verify in the iPhone 17 simulator, touch only the Ownership list, never
   push, and end with the report COMMON.md asks for (changes per commit, test counts before and after,
   how it was verified running, branch name, changelog lines, anything George must do, decisions George
   might reverse). The app puts each worktree under `.claude/worktrees/<slug>-<hash>` on branch
   `claude/<slug>-<hash>`. Write the brief file first and keep the prompt short; the brief is the contract.
4. **Wait.** The app continues you when a session ends its turn, with the first 400 characters of its
   report. Read the whole report with `mcp__ccd_session_mgmt__list_events` (`limit` 5). Do not poll.
   A session that asks for the simulator panel and gets no answer works from screenshots only; its report
   says what it could not tap, and that is your simulator checklist.
5. **Merge** into master in order: core/parser branches first, then UI, then the data-model branch last
   (`git merge --no-edit <branch>`). Conflicts are usually `ROADMAP.md` (keep both rows), a doc comment
   (keep both paragraphs), and a shared view file where one side removed code the other kept. Read every
   conflict region before resolving. Then `xcodegen generate`.
6. **Apply the cross-session follow-ups** the reports name ("session 32 should call session 31's
   helper"), stale comments and README lines, and anything a report says it edited outside its list.
7. **Run all three suites** (`scripts/test.sh`, in the background). Fix, do not skip.
8. **Check in the simulator** what no session could tap: the flows George will use first. Fix what you
   find, commit, rebuild, re-check. Keep this to the real risks; it is the expensive step.
9. **Write the notes** (§6): CHANGELOG section, What's New entry, `SettingsTests` pin. Record the round in
   `briefs/COMMON.md`. Add a memory line if a rule changed.
10. **Push master** (`git push origin master`) and send George the hand-over message: whether a CloudKit
    schema deploy is needed, the release commands, what to check on real devices (haptics, the Mac), the
    decisions sessions made that George might reverse, and session effort levels.

Lessons that cost time: sessions sometimes leave a Debug Mac app running or a spare simulator
("HITList-33"); check `pgrep -x HITList` and `xcrun simctl list devices` and tell George. A session that
stops early with coherent commits is finished best by you on master. A brief that says "touch only these
files" is obeyed; one that does not produces merge conflicts.

## 5. Brief ownership map (where things live)

- Quick add: `HITListCore/.../QuickAddParser.swift` (+ `+Disabled.swift`), `DateExpression.swift`,
  `RecurrenceRule.swift`; `HITList/Views/Popouts/QuickAddPopout.swift` (card), `QuickAddDraft.swift`
  (draft + sticky store), `QuickAddContext.swift`, `TokenHighlightField.swift` (highlights and tap targets),
  `QuickAddEntry.swift` (the "+" buttons), `PopoutHost.swift` (iPhone card placement, Discard bubble,
  toasts, sheets), `PopoutController.swift`.
- Task editor: `Views/Popouts/TaskPopout.swift` + `Views/Popouts/Editor/*` (cards, checklist, line field).
- Lists: `TaskListView.swift`, `Inbox/`, `Upcoming/`, `Tabs/` (iPhone shell: `MobileShell`, `MobileTabBar`,
  `BrowseView`, `ScreenMenu` = the top-right controls), `TaskRow.swift`, `ListChrome.swift` (`ListMetrics`),
  `Flipboard/`, `SidebarView.swift` + `ContentView.swift` (Mac).
- Sync: `Services/Sync/*` (`SyncLog`, `SyncWatchdog`, `SyncEnvironment`, `SyncAppDelegate`, `SyncRecovery`,
  `SyncStoreGuard`), `CloudSyncMonitor.swift`, `ModelContainerFactory.swift`, `Deduplicator.swift`.
- Model: `Models/Models.swift`, `SchemaVersions.swift`, frozen `SchemaV1Models.swift`, `SchemaV2Models.swift`.
- Settings: `SettingsView.swift`, `Views/Settings/*` (+ `Mac/`), `WhatsNew.swift`, `Support/Preferences.swift`.
- Design system: `Support/DesignSystem/*` (`HITTokens.swift` = fonts/spacing/colours; README).
- Delight: `Support/Delight/*` (sounds, haptics `TapHaptic`), `Views/Delight/*` (completion motion, toast).
- Notifications: `Services/NotificationScheduler.swift`, `Services/Notifications/*`.
- Nobody but the supervisor: `scripts/`, `briefs/`, `CHANGELOG.md`, `WhatsNew.swift`, `project.yml`
  (sessions may add files to it), this file.

## 6. Releases and notes

- Versions: `## X.Y.Z` section in `CHANGELOG.md` (unreleased sections have no stamp; the release script
  stamps "— build N, date"), an `Entry(version: "X.Y.Z")` at the top of `WhatsNew.swift`, and the pin in
  `SettingsTests` (`XCTAssertEqual(current.version, "X.Y.Z", "this round's list")`). All three or the
  preflight fails.
- **Frozen once released.** George releases between rounds. Before touching the notes run
  `git log --oneline -5` and look for a "Release X.Y.Z (N)" commit: that version's section and entry are
  frozen; new work goes under the next version. Getting this wrong twice is why this rule exists.
- The command George runs (from the HITList folder):
  `scripts/release.sh --version X.Y.Z --quick` then `git push origin master --tags`. `--quick` runs
  core + Mac tests as preflight (you ran iOS already). The script checks CloudKit schema drift first,
  bumps the build, regenerates, tests, archives and uploads both platforms, commits "Release X.Y.Z (N)"
  and tags. If it fails after bumping, the tree is dirty:
  `git checkout -- project.yml HITList/Info.plist HITList.xcodeproj/project.pbxproj`.
- **Schema deploy.** If any model changed, or a Debug run exercised a field Production lacks, George must
  first open the CloudKit Console → iCloud.com.trammells.hitlist → Development → Deploy Schema Changes… →
  Deploy to Production. Say so in bold in the hand-over message. The script refuses to upload while the
  environments differ.
- TestFlight: George's own devices get builds at once. Friends are external testers: the first build
  for them goes through Beta App Review (up to a day), needs App Store Connect's Test Information filled
  in (description, feedback email, a privacy policy URL), and "Sign-in required" stays unchecked while the
  app has no login of its own.

## 7. Decisions George has made (do not re-ask)

Theme dark only. No light mode, no right sidebar, no collaboration, comments or boards. Quick-add times
are 24-hour unless am/pm is typed ("tom 13" = 13:00; "tom 4" = 04:00, kept on purpose). Monthly repeats
keep their original day; a repeating task typed after its time starts at the next occurrence; repeat
rules store their time of day. `tom` stays a shortcut; tapping a highlight disables that token; highlights
are rounded like buttons. No fast-tap undo: undo only via the toast or the Completed list. "Sticky drafts"
means only that an open card with text survives app switches and a kill (one card per list, cleared on
close), never a reopenable draft system; tapping away asks Discard whenever the card has any content. A
popout on a task deleted elsewhere closes itself. Sub-tasks are one level, a checklist: never rows of
their own, no date/priority/labels of their own, completing the parent completes them, completing the last
one does not complete the parent. "next mon" on a Sunday means tomorrow. Completion: one staccato haptic
(rigid impact), toast is one big button beside the "+" on iPhone. The Mac window hides on close and comes
back on Dock click or ⌘Tab. iPhone list titles 16 pt with −0.3 tracking, card title 19 pt, Mac rows 15 pt
(14 was too small). The iPhone keeps a four-tab shell with the "+" oval above the tab bar; the Mac keeps
the sidebar; settings open in-window on the Mac (`MacSettingsPage`), as a sheet on iPhone.
From 2026-11-04/05: tabs Inbox · Today · Upcoming · Flipboard, Browse behind the top-right magnifying glass and
Settings behind Browse's gear; the profile sits top-left (Mac sidebar, iPhone Browse); no login system ever (the
Apple account is the identity, profiles serve Shared Tasks); the Claude integration is off and hidden by default,
its privacy choices shown only once switched on; "Delight" is called "Extras"; a quick-add highlight goes away by a
click/tap or by Backspace right after it; "!" reminders light up only once complete (after a space); `!15m` = 15
minutes from now, `!15mb` = before the due time; a Discard question sits inside the card it concerns; overridden
quick-add phrases stay in the title as plain text; the Mac board always opens on today. Follow Apple's HIG
(`briefs/HIG-NOTES.md`); George's explicit choices win where they differ (pointing hand over highlights).

## 8. Where things stand (2026-11-05, after round 11)

Round 11 (briefs 47–52) is merged for 0.7.0 (17): highlights on native text views (Backspace removes a highlight
first; steady Mac pointer), `!15m` = from now with schema V5 `TaskItem.reminderDate` (George deploys it), Extras and a
switched-off Claude integration, the iPhone Duo's side tab island and squeaky hinge, the Shared Tasks preview on its
own container `iCloud.com.trammells.hitlist.shared` (George deploys its schema too; `release.sh` now checks both
containers), TipKit tips, Spotlight, Mac Settings polish, dead-file cleanup. Supervisor follow-ups: reminder taps open
their task (`IntentRouter`), side-store Debug runs keep their own settings suite, the launch no longer waits on the
push service (27.7 s black screen after a cold boot → 2.4 s), and `HITListUITests` (`scripts/test.sh ui`).
Tools now: `scripts/window-shot.sh` and `scripts/window-drive.sh` (George granted screen recording and
Accessibility on 2026-11-05) let any session see and drive its own Debug Mac app; XCUITest drives the iPhone app with
no panel permission. Open items: COMMON's Round 11 record, plus a board card's meta line truncating ("5:38…", "S")
when a reminder bell joins it, and an intermittent iOS focus-release test (`testFocusFollowsTheOwnerBothWays`).

## 8a. Round 10 state (kept for the record)

Round 10 (briefs 39–46) is merged for 0.6.0 (16), no schema change: the Mac board's inline add card, the profile
top-left (Mac sidebar, iPhone Browse), Flipboard rightmost again, quick-add polish, account-switch hygiene and sync
hardening, the Claude connector (`hitlist-mcp` helper inside the Mac app, label-based privacy, `docs/connect-claude.md`
at /claude/), App Intents (Siri, Shortcuts), holiday effects and the rare sky whale, and iPhone Duo layouts (outer
display = tabs, inner = sidebar shell with an editor column). Open items are in COMMON's "Round 10 record". Shared
Tasks was deferred on purpose: SwiftData has no CloudKit shared-database support, so it means Core Data + CKShare,
a round of its own. George has not yet invited friends (TestFlight external group, Beta App Review).

## 8b. Round 9 state (kept for the record)

Round 9 (briefs 34–38) is merged for 0.5.0 (15): Settings → Account with a synced `Profile` (schema V4, in
CloudKit Development until George deploys it), the privacy policy on GitHub Pages
(https://aeronyx.github.io/HITList/privacy/, from `docs/`; the repo is public since 2026-11-04), the iPhone tabs
Inbox · Today · Flipboard · Upcoming with Browse behind the magnifying glass, the taller editor and bigger
Confirm, superseded quick-add phrases and joined highlight boxes, and the Mac Upcoming board. 0.5.0 is the first
build meant for friends as external testers (Beta App Review). Open small items: tapping the dimmed list above
an editor with typing blocks the close without asking Discard (iOS reports no dismiss attempt); the Mac board's
cards use the 13 pt row title (`TaskRow` fixes it); the Mac Confirm pill stayed 34 pt. ROADMAP has a row per
brief through 38. Starting sessions: the app refuses `start_session` with "user_asked" on a turn opened by a
background task or another session's note, so start a round's sessions on a turn George began, or propose
them as cards ("own_initiative") for George to click. Sessions ask George for simulator tap access in their
own panel; tell George to grant it when they ask.
