# HITList supervisor handbook

For the Claude Code session that runs HITList rounds in this folder: reads George's feedback, writes
briefs, starts Opus 5.5 sessions in worktrees, merges and tests their branches, checks the result in the
iPhone simulator, writes the release notes and hands George the release command. Fable 5.1 did this for
rounds 1–8 (2026-10-26 to 2026-11-04), an Opus 5.5 session for rounds 9–12 and 15, Fable for 13–14; from round 16
(2026-11-10) a Fable 5.2 chat does it. Read this file first, then `dev/briefs/COMMON.md` (the facts every delegated
session reads), then the newest queue, `dev/briefs/ROUND-16.md` (round 16 is merged; its record is in COMMON).
The memory folder under `~/.claude/projects/-Users-gtrammell-Desktop-HITList/memory/` is loaded into every
session in this folder and holds the same rules in shorter form; keep both in step when something changes.

## 1. The app and the person

HITList ("Human-in-the-List") is George Trammell's personal Todoist-style task app: SwiftUI, SwiftData with
CloudKit (`iCloud.com.trammells.hitlist`, private database), iOS 18+ and macOS 15+, dark slate theme only
(George never uses light mode), Inter typeface through `HITType` roles. `HITListCore` is a pure Swift
package (filter language, quick-add parser, dates, recurrence, ordering, snapshot JSON); `HITListTests` is
the app test bundle (in-memory container, hosted in the app, runs on the iPhone 17 simulator and the Mac).
George uses the app every day on an iPhone 16 and a Mac, both on TestFlight; a few friends use it too,
as internal TestFlight testers since 2026-11-10 (§6). `dev/ROADMAP.md` is the plan and the log of every round; `dev/DESIGN.md`
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
  tools). Xcode 27.2 (SDK 27.2), macOS 26.7.1 on George's Mac. Every Mac look so far was checked on 26.7.1 only.
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
- The Mac: since 2026-11-05 a session captures and clicks its own Debug Mac app with `scripts/window-shot.sh` and
  `scripts/window-drive.sh` (single windows only, never `/Applications/HITList.app`). Launch it with
  `HITLIST_STORE_SUFFIX=<name>` and `-disableCloudKit YES -ApplePersistenceIgnoreState YES`. Real-device feel
  (haptics, font smoothing on George's display) still needs George's eyes: list it.
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
- Every optional model field goes into `-seedSampleData` the day it is added
  (`CloudKitSchemaTests.testSampleDataCarriesEveryOptionalField` fails otherwise), and the schema push run
  (`HITLIST_STORE_SUFFIX=schema`, sync on) happens before the release that needs it. Development learns a field only
  from a record that carries it, sessions run with sync off, and `release.sh`'s Development/Production diff cannot
  see a field missing from both: three `TaskItem` fields from 0.4.0 went undeployed for a week that way, and the
  first flip of a switch on a friend's Mac stopped his sync for good (2026-11-06). `release.sh` now also fails its
  preflight while Production lacks a field the models have (`CloudKitSchemaCheck`).
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
- The home-server backup prototype (`server/`, `BackupService.swift`, `Keychain.swift`) was never wired in and was
  removed on 2026-11-05; it is in history before `v0.7.1` and described in `dev/DESIGN.md` §5.

## 4. A round, step by step

1. **Read the feedback** and split it into sessions by file ownership, not by topic size: two sessions
   must never edit the same region of a file. Three parallel sessions is the sweet spot; the fourth
   waits. A session gets one coherent area (a parser, a screen, a data-model change plus its UI).
2. **Write one brief per session** in `dev/briefs/NN-slug.md` (next number after the highest; 33 was the
   last of round 8). Each brief has: George's words quoted verbatim; numbered items ("one commit each,
   failing test first where there is logic"); an **Ownership** list of files; a **Done** section (what
   must be visible in the simulator and which suites must be green); which files it must not touch
   because a sibling owns them. Update `dev/briefs/COMMON.md`'s "Round N ownership" block and "How sessions
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
   (`git merge --no-edit <branch>`). Conflicts are usually `dev/ROADMAP.md` (keep both rows), a doc comment
   (keep both paragraphs), and a shared view file where one side removed code the other kept. Read every
   conflict region before resolving. Then `xcodegen generate`.
6. **Apply the cross-session follow-ups** the reports name ("session 32 should call session 31's
   helper"), stale comments and README lines, and anything a report says it edited outside its list.
7. **Run all three suites** (`scripts/test.sh`, in the background). Fix, do not skip.
8. **Check in the simulator** what no session could tap: the flows George will use first. Fix what you
   find, commit, rebuild, re-check. Then, before the hand-over, screenshot every main screen on both platforms
   (Inbox, Today, Upcoming, Flipboard, Browse, a Group, Settings; the Mac's equivalents) with demo data
   (`-seedDemoData`) and look at each as George would: a name shown twice, two controls that look alike, two fonts in
   one header, a control nobody asked for. Send the screenshots with the hand-over. 0.8.0 shipped an Inbox with all
   four of those because the supervisor looked at Today and the Flipboard and never opened the Inbox. A session's
   report that says two things look alike, or that it could not check something, names an item for you to fix.
9. **Write the notes** (§6): CHANGELOG section, What's New entry, `SettingsTests` pin. Record the round in
   `dev/briefs/COMMON.md`. Add a memory line if a rule changed.
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
- Nobody but the supervisor: `scripts/`, `dev/briefs/`, `CHANGELOG.md`, `WhatsNew.swift`, `project.yml`
  (sessions may add files to it), this file.

## 6. Releases and notes

- **From 2026-11-10 the version stays 0.9.0** (George: "definitely don't update the major version number for a
  while"). Every release is a new build of 0.9.0: `scripts/release.sh --quick` (no `--version`), then
  `git push origin master --tags`. A new version number would send the external group's build back to Beta App Review
  (one review per version, per platform). The rules below about version sections apply again only when George asks
  for a new version.
- **Notes for a build** (N = the build about to be made, one more than `CURRENT_PROJECT_VERSION` in `project.yml`):
  a `## 0.9.0 (N)` section at the top of `CHANGELOG.md` (unstamped; the script stamps "— date"), an
  `Entry(version: "0.9.0", build: N, items: […])` at the top of `WhatsNew.swift`, and the pin in `SettingsTests`
  (`XCTAssertEqual(current.label, "0.9.0 (N)", "this round's list")`). `release.sh` stops before anything slow when
  the section is missing, and its preflight fails when the running build is newer than the newest entry
  (`WhatsNew.isBehind`). An entry and section are frozen once their "Release 0.9.0 (N)" commit exists.
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
  **Two containers since 0.7.1:** `iCloud.com.trammells.hitlist` (tasks) and `iCloud.com.trammells.hitlist.shared`
  (Shared Tasks, its record types reach Development through `-sharedTasksSchemaPush YES` runs). Each is deployed on its
  own in the console: pick the container in the menu at the top first. `release.sh` checks both; 0.7.0's release
  stopped because only the first had been deployed. Check either yourself, read-only:
  `xcrun cktool export-schema --team-id UC8N98H3RT --container-id <container> --environment production --output-file x.ckdb`.
- TestFlight: George's own devices get builds at once, and so do the friends since 2026-11-10: they are internal
  testers (App Store Connect users on George's team, limited to HITList), with no Beta App Review. They may also still be
  in the public-link external group, which is harmless. For external testers the first build of each version goes
  through Beta App Review (up to a day), needs App Store Connect's Test Information filled
  in (description, feedback email, a privacy policy URL), and "Sign-in required" stays unchecked while the
  app has no login of its own. The group's "Test iPhone and iPad apps on Macs with Apple silicon" setting stays
  off: with it on, TestFlight on a Mac offers the iPad build beside the Mac app, and the first friend on a Mac
  installed that one (2026-11-06). The iOS build opts out of Macs since 0.7.2 (`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD:
  NO`); a "check on the Mac" always means the macOS build.

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
quick-add phrases stay in the title as plain text; the Mac board always opens on today. From 0.7.1: no Mac button
hands you off to Mail (copy the address and say so); the bolt's lightning strike is a rare "you're good to go" (launch,
back after a minute away, recovered after a minute of trouble), never a per-sync animation. Follow Apple's HIG
(`dev/briefs/HIG-NOTES.md`); George's explicit choices win where they differ (pointing hand over highlights).
From 2026-11-07 (after 0.8.0): a screen's name appears once, as its title; iPhone titles are large and never
buttons; beside the magnifying glass a list has one control, the view options; the Inbox sorts by Priority (flat,
priority then date) by default, Group ("Ungrouped" last) and Date are the other sorts, Today by Priority or Group;
saved filters live in Browse's search field on iPhone, the Inbox has no filter control; one section-header style; Groups
first in Browse, above Shared Tasks; switching tabs returns the other tab to its first screen; shared tasks are rows in
your lists, the Shared Tasks screen is for the lists themselves.
From 2026-11-08 (round 15, superseding the last clause): shared tasks are one forced Group, Shared Tasks, last in every
list of Groups; a shared task looks like yours with the people's pictures where labels go and opens in the same editor;
Sharing… sits in that Group's view options. The editor's title reads quick-add phrases typed in it (words already in
the title stay plain). Every accent-filled control (the "+", Confirm) has the theme's dark `onAccent` glyph, the same
in a background window; the Mac toolbar's "+" is one capsule. The Mac sidebar from the top: profile, Search (⌘F),
Inbox …; Groups (Shared Tasks last), Filters, Labels; a filter's query in the toolbar reads "Search: …". Rows: Inter
14/12 on the Mac, drawn without font smoothing, 17/13 on every iPhone. Tips never push the layout and close on a tap
anywhere on them. The bolt has two styles in Extras (Slam by default) under the same rare gate. Adding or editing a
Flipboard switch is a small card, never a sheet; every switch tile on a screen is the same size.
From 2026-11-10 (round 16): the version stays 0.9.0 until George says otherwise; each release is a new build of it.
Switches are routines first: by default a switch never appears as a task anywhere (this replaces round 13's "a red one
is in Today"); "Overdue becomes task", on a switch or on its Switchboard, opts it in from the moment it is due.
Switchboards group switches, Daily or Weekly, each with a reset time (04:00 for a new one; loose switches keep
midnight); a switch belongs to at most one, and existing switches stay loose. A switch's time is when the step is due
and reminds then. The Flipboard is a calm status check, not a second to-do list. The bolt's twirl is a spin about the
vertical axis (edge-on on the way round); the slam is kept as it is. On the Mac, anything the system decides by macOS
version or by which view holds the keyboard is drawn or pinned by us (the sidebar's rows and selection, the toolbar's
band, pill and toggle); nothing takes the keyboard at launch. The four Switchboard choices were the supervisor's
(George: "work freely"), so George may still reverse them: see `dev/briefs/ROUND-16.md`.

## 8. Where things stand (2026-11-10, round 16 merged)

**2026-11-10, round 16 merged for 0.9.0 (21) (Fable 5.2 supervisor).** Briefs 70–73 ran as four Opus sessions at once
and are merged on master: the Mac's chrome drawn by us for macOS 27 (a friend's 27.2 drew 0.9.0 (20) with a grey
selection, a dark band behind the first header and filled toolbar glass; nothing here runs 27, so the friend's next
screenshot is the check), monthly and yearly repeats in quick add, Switchboards (schema V6, pushed to CloudKit
Development by the supervisor; George deploys it), Browse's last row and swipe to delete, the bolt's coin spin. Notes
are per build now (§6). Details and leftovers in COMMON's Round 16 record. Next: the friend's screenshot of build 21 on
macOS 27.2, George's word on the Switchboard choices, and whether to own the sidebar's shape (our own split view).
The next brief number is 74.

### Before round 16 (kept for the record)

**2026-11-10, 0.9.0 (20) released; handed to a Fable 5.2 chat.** George released 0.9.0 on both platforms. Both builds
sat in Beta App Review because 0.9.0 was a new version for the external (public-link) group. The friends are now
internal testers, and the version stays 0.9.0 from here on (§6). George's and a friend's notes on 0.9.0 are queued
in `dev/briefs/ROUND-16.md`, with what the Opus supervisor found first:
- **A friend's Mac looks different.** Same build; most likely a newer macOS than George's 26.7.1, so ask for his
  version first.
- **Switchboards and routine switches:** schema V6, and George deploys.
- **Monthly quick-add phrases.**
- **Browse:** its bottom button behind the home bar, and swipe to delete a Group.
- **The bolt's twirl** as a coin spin.

No brief is written yet; the next number is 70.

**2026-11-08, round 15 merged as 0.9.0 (Opus supervisor).** Six sessions at once (briefs 64–69: Shared Tasks as one
Group, the editor's quick add, the Mac's toolbar and sidebar search, type, the bolt's slam, the Flipboard's add card),
after the supervisor's fix for the Mac's invisible picker cards (with the Xcode 27.2 SDK a SwiftUI content view draws
over an AppKit view added inside it; `PickerLayerHost` now lives in the window's frame view). That fix was 0.8.2, never
uploaded; its notes fold into 0.9.0. George's last tweaks, by the supervisor: the Mac "+" drawn like the Confirm pill,
tips hanging outside the quick-add card and closing on any tap, the Flipboard's lights staying on their switches with
tiles of one size (a forked helper). New for step 8: `HITListUITests/ScreenTourUITests` screenshots every main iPhone
screen (`TEST_RUNNER_HITLIST_TOUR=1`, see its header). A Debug Mac app may open no window (it restores the real app's
saved state): launch it with `-ApplePersistenceIgnoreState YES`. Next: George's and the friends' notes on 0.9.0; two
Apple accounts sharing.

**2026-11-08, round 14 merged as 0.8.1 (Fable).** 0.8.0 shipped an Inbox George called a mess (a small title that was
a button, two filter-looking controls, "Inbox" twice, two fonts in one header) because the supervisor merged brief 57
without opening the Inbox. Round 14 (briefs 61–63) put it right: large titles, one view-options control, Sort by
Priority/Group/Date, filters in Browse's search field, Groups first in Browse; shared tasks are rows in Today, Upcoming
and the Inbox (`ListRow`, `SharedRows`) with a Shared section in the Mac sidebar; the Duo's outer display has larger
rows and a roomier island; leaving a tab resets it. §4 step 8 now requires the screenshot pass and the screenshots in
the hand-over; §7 holds the rules. Next: George's feedback on 0.8.1; two-account shared tasks with a friend.

**2026-11-07, round 13 merged (Fable).** Briefs 57–60 (Groups, tab motion, Flipboard intervals, Review Inbox) ran as
four Opus sessions at once and are merged on master as **0.8.0**, together with the day's fixes (the iPad-on-Mac opt-out,
the schema seed and preflight check, the watchdog). George deployed the three fields and switched the Friends group's
iPad-on-Mac setting off before the round. Flipboard rule now: a green switch is on the board only; a red one is in Today
and the Inbox as today's task until flipped; Upcoming shows none; `@flipboard` in a query opts out. The Inbox and Today
group by Group or priority (`GroupedOrdering`), the Inbox has a filter (a query built by chips), iPhone titles are
menus of Groups and labels. Review Inbox takes only undated, ungrouped tasks as a swipe card (`InboxReview`,
`InboxReviewSwipe`). Details and the leftovers in COMMON's Round 13 record. Next: George's own feedback on 0.8.0.

**2026-11-07, the friends' first week (Fable).** The first friend on a Mac installed the iPad build from TestFlight
(the Friends group allowed iPhone and iPad apps on Apple silicon Macs; the iOS build now opts out and the group
setting goes off), and his sync stopped at the first flip of a switch: `TaskItem.deadline`, `locationName` and
`flipPeriodStart` had never reached either CloudKit environment (`-seedSampleData` did not set them; the drift check
is blind to a field missing from both). Fixed on master: the seed carries every optional field, `CloudKitSchemaTests`
pins that and checks Production during `release.sh`'s preflight, the watchdog ignores TipKit's saves (its
`Core*Record` entities post `ModelContext.didSave` too), the sidebar's "Preview" badge yields, `-seedDemoData` fills a
side store for screenshots (the README has them). George deploys the three fields. Round 13
(`dev/briefs/ROUND-13.md`; briefs 57–60: Groups, tab motion, Flipboard intervals, Review Inbox) is written and waits
for George's word on who runs it. The notes for the next version are under `## 0.7.2`.

**2026-11-05, repository tidied for public view (Fable).** The repo is public and read by people who do not
know the project. Process docs moved under `dev/` (this file, `ROADMAP.md`, `DESIGN.md`, `briefs/`); `CLAUDE.md`
points here. `README.md` is for readers: what the app is, how it is put together, how to build, test and release.
Keep it short and current when a round changes any of that, and keep round history out of it. Removed (all in
history before `v0.7.1`): `TESTFLIGHT.md`, `scripts/session.sh`, `scripts/sdk_session.py`, `server/`,
`BackupService.swift`, `Keychain.swift`. CI: `TaskActions.toggleCompletion` takes `now:`, so the Claude tool test
no longer depends on the wall clock (it failed on the UTC runner the moment UTC passed the date the test
hard-coded, and would have failed locally a day later, stopping `release.sh`'s preflight). Never compare a
hard-coded date with code that reads `Date()`: inject the clock. A red run on master is a real failure until the
log says "not acquired by Runner". Actions are on current majors and every master commit gets its own run.
Commit subjects on this repo say what changed and why in one line; no session or round narrative.

Round 12 (briefs 53–56) finished the Friends build, released as **0.7.1 (17)**: 0.7.0's release stopped at the Shared
Tasks container's schema check (only the task container had been deployed), so nothing shipped and its notes ship as
0.7.1 with George's last fixes. The Mac's Send Beta Feedback copies george@trammells.com and shows the card, never
Mail (iPhone and iPad still start a mail). The bolt strikes only as a "you're good to go": the first good sync after
launch, after a minute or more away, or after a minute or more of sync trouble (`BoltStrikeGate`; on the Mac an import
follows activation within about a second, so the strike on return is prompt). The 26 merged session worktrees were
removed (17 GB). Details in COMMON's Round 12 record; round 11's open items below were fixed in round 12. Next:
the friends' TestFlight feedback.

Round 11 (briefs 47–52) is merged for 0.7.0 (17), which shipped as 0.7.1: highlights on native text views (Backspace removes a highlight
first; steady Mac pointer), `!15m` = from now with schema V5 `TaskItem.reminderDate` (George deploys it), Extras and a
switched-off Claude integration, the iPhone Duo's side tab island and creaky hinge, the Shared Tasks preview on its
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
