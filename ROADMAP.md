# HITList Roadmap

Backend and robustness work, in priority order. Written 2026-10-27, after TestFlight build 1 (0.1.0)
shipped to George's iPhone 16 and Mac. UI/UX iteration runs in parallel in separate sessions and is
not tracked here.

Guiding principle: items that get more expensive once other people's data lives in the Production
CloudKit container come first.

## Status

| # | Item | Status | Owner |
|---|------|--------|-------|
| 4 | Git baseline + one-command release script | done 2026-10-27 | Fable (this session) |
| 1 | Multi-device dedupe for seeded filters, projects, labels | done 2026-10-27 | Opus 5.5 session, effort High |
| 2 | Versioned schema + migration plan + schema rules | done 2026-10-27 | same session as 1 |
| 3 | Move the store into an App Group container | done 2026-10-27 | same session as 1 |
| 5 | Sync resilience (account change, reset cache, auto backup, status row) | done 2026-10-28 | Opus 5.5 session, effort High |
| 6 | Reminder robustness (reschedule on import, actions, time zones) | done 2026-10-28 | Opus 5.5 session, effort High |
| 7 | App-layer tests + GitHub Actions CI | done 2026-10-28 | Opus 5.5 session, effort Medium |
| 8 | Calendar (EventKit), themes, preferences | UI sessions | |
| 9 | Filter language (Todoist parity, autocomplete, editor) | done 2026-10-28 | Opus 5.5 session, effort High |
| 10 | Sync robustness: log, watchdog, environment, push diagnostics | done 2026-11-02 on branch `sync-robustness`: sync log (Settings → iCloud → Sync log; Copy, Share/Save; mirrored to os.Logger at notice so `/usr/bin/log` keeps it), 5-second watchdog (export after save, import after push, stuck after 60 s, how late), CloudKit environment and channel in Settings, push registration and pushes logged, "Sync paused: stuck" with Relaunch, Development builds on their own store. Cause of George's Nov 1 Mac issue found in the store and system log: an import that never ended blocked every export for the rest of the session. Verified on the Mac (Debug build, side stores): saves exported in 0.4–0.7 s; the container registers for pushes itself right after setup; coming back after 1 min away imports within 1.9 s; a simulated never-ending import is stuck at 62 s and turns the bolt at 120 s; Relaunch reopens; a reset store re-imports in 0.5 s; a Debug build without a suffix opened HITList-Development.store. iPhone 17 simulator (no account): logs no errors, bolt struck through. Remains: a push between two real devices (one Mac never pushes to itself), the iPhone background push, network off on real hardware, the stuck case on a TestFlight build | Opus 5.5 session, effort Max |
| 11 | Beta-readiness review | done 2026-11-02 on branch `beta-review`: 12 fixes, each test-first: a reset now lands only on the store that asked (and each store keeps its own Trash); a store that won't open no longer crashes every launch (in-memory, file untouched, reset offered); Debug runs no longer clobber the TestFlight app's backups, reminders and badge, and `-seedSampleData` never touches HITList.store; backups/Export JSON carry the V2 fields; reminders follow every local save (completing or deleting from a list used to leave the reminder); a stale Complete/Snooze no longer skips a recurring occurrence or undoes a move; overflow crash in quick add; first imports get 10 min before "stuck" and sync times are per store; SyncEnvironment from the signed entitlements, TestFlight never Development (every channel tested); Diagnostics and Check iCloud name the real environment; sticky drafts keep location and deadline; a blank popout title is put back. Verified on the iPhone 17 simulator (no iCloud: "no account" and setup failure logged as notices; edge titles; recurring complete/undo; SIGKILL mid-draft → text, location and deadline back; reset → own Trash) and the Mac Debug build (CloudKit Development, own store: exports 1.1–1.7 s after saves, reminders and backups stood down, reset re-downloaded everything in 0.93 s, HITList.store untouched). Decisions for George in the session report | Opus 5.5 session, effort Max |
| 12 | Dates, times and repeats the way George reads them | done 2026-11-02 on branch `dates-and-times`: monthly/yearly repeats keep their day (Jan 31 → Feb 28 → Mar 31; Feb 29 → Feb 28 → … → Feb 29), stored as a fourth rule part (`monthly;1;;31`) that older builds ignore, anchored by quick add and on the first completion of an unanchored rule; a repeating task typed after today's time starts at its next occurrence ("every weekday 9am" at 2 pm → tomorrow 9:00; explicit dates kept); times are 24-hour unless am/pm is typed ("at 5" = 05:00, "tom 13" = tomorrow 13:00, "Buy 3 apples" untouched). Test-first; checked in the running iPhone 17 simulator app via a temporary in-memory hook (parsed and completed tasks printed) | Opus 5.5 session, effort High |
| 28 | Quick-add card: tappable token highlights, sticky = "don't lose it" | done 2026-11-02 on branch `quick-add-card`: tapping/clicking a highlight switches that token off (words stay in the title, chips let go; `QuickAddParser.parse(_:disabling:)` in the new `QuickAddParser+Disabled.swift`, keyed by kind + words so it survives typing on); highlights are 4 pt rounded boxes placed from the text's real line layout (`Text.LayoutKey`), on the Mac now aligned with the TextEditor's 5 pt inset; only the open card is stored (with its id and list), it reopens at launch after a kill, a fresh card never gets it, every close clears it. Verified: tests (core +11, app +15), iPhone 17 simulator relaunch with a stored card twice (card back in its list with description and a switched-off "Tom"). Not tapped by hand: the simulator and Mac UI can't be driven from the session | Opus 5.5 session, effort High |
| 30 | Final review before 0.4.0 | done 2026-11-02 on branch `beta-final-review`: 6 fixes, 5 of them test-first: picking "Every month" again in the task popout dropped the anchor and a "31st" task repeated on the 28th; ⌘N over the open Mac panel kept the old card, whose draft came back at the next launch after it was closed; a Debug build on the Mac reopened (and discarded) the TestFlight app's open card (now one key per store); on titles longer than four lines the highlights and their tap targets sat on the wrong words (a tap could switch off an unseen token); a pasted line break glued words ("Buy milkBuy eggs"); quick add parsed the title four times per keystroke (7.0 → 1.75 ms with a 500-character title, Debug). Interaction checks held (tom 13 with "tom" off, the restored card vs the toasts, the deleted-task check vs an open card, Discard at launch). Date rules tested on America/New_York (2027 DST days, year ends, leap days, Monday/Sunday weeks, weekdays across a weekend); known and not fixed: a repeat timed inside the skipped DST hour stays an hour late (XCTExpectFailure). Verified on the iPhone 17 simulator (card back after a kill with "tom" off and its description; long title with no misplaced highlights), the Mac Debug app's launch and sync log (own store, reminders and backups stand down, import 1.3 s), and the Mac views in hosted windows (highlight vs editor hit-testing; a second window's delete closes the panel). Real clicks in the Mac app, Relaunch and the Sync log screen need George's eyes | Opus 5.5 session, effort Max |
| 33 | Haptics, Undo toast, add buttons, type size, Mac reopen (brief 33) | done 2026-11-03 on branch `feel-and-chrome`: the Mac window is hidden on close and shown again by a Dock click or ⌘Tab (open → on screen ~280 → ~136 ms in Debug, same window, no ContentView rebuild; sync log now records background on close); iPhone "+" 76 × 50 / 28 pt, Mac toolbar "+" oval 58 × 36 → 50 × 30 pt (14 × 10 label, 10 pt glyph); one rigid 0.75 bump for the "+", the confirm pill and completion (was the two-tap .success), Haptics toggle honoured; the whole Undo toast is the button, 48 pt tall, content-sized, left of the iPhone "+" and centred on it, bottom-trailing on Mac/iPad, swipe down or sideways dismisses without undoing; iPhone row titles 17 → 16 pt with −0.3 tracking (new `HITType.taskTitle`), row line 22 → 21, quick-add title 20 → 19. Verified on the iPhone 17 simulator and with timed Debug runs of the Mac app; haptics and Mac clicks need George | Opus 5.5 session, effort High |
| — | External TestFlight / App Store prerequisites | before friends | George |

### UI

| Item | Status | Owner |
|------|--------|-------|
| Completion delight (sound, strike-through, slide-away, undo toast) | done 2026-10-28 | Opus 5.5 session, effort High |
| Completion sounds (five built-ins + custom file) | done 2026-10-28, awaiting George's ears | Opus 5.5 session, effort Medium |
| Upcoming view (week strip, day sections, drag to reschedule) | done 2026-10-28; iPhone drag conflicts with the row context menu (verified 2026-10-31), fix in the popouts brief; Mac drag unverified | Opus 5.5 session, effort High |
| Inbox polish (empty state, count, Process mode) | done 2026-10-31 | Opus 5.5 session, effort High |
| Task Flipboard | done 2026-10-28 | Opus 5.5 session, effort High |
| Design system (custom buttons, toggle, chips, fields, sheet chrome; editors, Settings, sidebar "+", "…" menu) | done 2026-10-31; guide in HITList/Support/DesignSystem/README.md | Opus 5.5 session, effort High |
| Task popouts (no detail column; quick-add card with live chips, floating "+", inline add rows; task popout; iPhone Upcoming rows no longer drag) | done 2026-10-31; iPhone 17 simulator checked (floating "+", typed tokens → chips, Return keeps the card open, row → task sheet, … menu moves); ⌘←/⌘→ move the open task a day on Mac; Mac panel, inline add row and drag-to-day need George's eyes | Opus 5.5 session, effort High; merged and smoothed by Fable |
| Inter typeface everywhere, schema V2 (reminder offset, deadline, location, Flipboard charge fields), shared due colours | done 2026-10-31 | Fable |
| iPhone tabs + four screens (Inbox/Today/Upcoming/Browse, oval "+"; priority-then-due sort, Inbox rule, "Group" wording) | done 2026-10-31; iPhone 17 simulator checked (all four tabs, Group pushed from Browse with the "+", search finds a completed task, Today's two sections with time-only rows, Group note absent from Inbox, strip jump); real taps on the bar and Mac sidebar wording need George's eyes | Opus 5.5 session, effort High |
| Quick-add v2 (oval card, '+' options, reminder offsets, deadline, location) | done 2026-10-31; iPhone 17 simulator recorded (type "Haircut tom 11am p1 !15mb" → Tomorrow / P1 / 11:00 AM · 15 min before, location from "+", save, task popout deadline + offset change); notification at due − offset ("in 15 min · Haircut") unit-tested; Mac panel and the "+" menu tap need George's eyes | Opus 5.5 session, effort High |
| Flipboard: long-press menu, faint-green lamp, charging switches | done 2026-10-31; iPhone 17 simulator checked (recorded); Mac long-press popover and right-click menu need George's eyes | Opus 5.5 session, effort High |
| Versioned releases: CHANGELOG.md, `release.sh --version`, preflight tests (core, macOS, iOS) before any archive, version in Settings → About; quick-add title 20 pt; `Preferences` keys; 6 pt sync dot | done 2026-10-31 | Fable |
| iPhone chrome v2 (floating island bar, filter-lines view options + "…" menu with Settings, the version and the sync dot on every screen, Liquid Glass on iOS 26, confirm-before-delete dialog, week start wired through) | done 2026-11-01; iPhone 17 simulator checked (island with the list showing through, "+" above it, "…" on Today and Inbox with Settings opening from it, Inbox's Process in the "…", glass quick-add card over the dimmed list, sync dot orange when signed out); a pushed Group's Edit…, the Flipboard "…", Reduce Transparency fallback and the real phone need George's eyes | Opus 5.5 session (items 1–2), finished by Fable |
| Settings v2 (sync confirmation and check, notification test, default reminder offset, morning summary, start screen, week start, app badge, confirm delete, diagnostics, What's new) | done 2026-11-01; session checked the Settings groups and the Reminders rows in the simulator and the Check iCloud / test notification on the Mac; Fable checked Settings opening from the "…"; the test notification, morning summary and badge on the real phone need George's eyes | Opus 5.5 session, effort High; cleanup and merge by Fable |
| Motion roles, four dark themes, Liquid Glass in the design system | done 2026-10-31 on branch `motion-themes`; `hitGlass` + six `HITMotion` roles; Slate/Graphite/Midnight/Moss switch live (WCAG AA tested); glass on the sheet header, segment highlight and chip hover; crisper completion pop + slide-away. iPhone 17 simulator checked (all four themes on Today, a Group, Settings/Appearance and the Flipboard; one Slate completion; glass header vs Reduce Effects). The list views' toast/collapse curves (not this session's files) and the Mac need George's eyes | Opus 5.5 session, effort High |
| Build-6 feedback: card put-away, no inline add row on iPhone, grey empty states, uniform rows with the Group trailing, Browse/list bottom margin, Mac oval "+", Review Inbox in the "…", design-system Done buttons, Mac title field box | done 2026-11-01; iPhone 17 simulator checked (Browse scrolls clear of the island, Settings row reachable); Mac items need George's eyes | Fable |
| Mac pickers inside the window (HITCalendar, time and reminder cards) | done 2026-11-01 on branch `mac-pickers`; no `NSPopover` or system `DatePicker` left in the popouts. Mac app run with a scripted, uncommitted demo (in-memory store): all 7 quick-add cards and all 8 task-popout cards opened inside the window at the minimum 760 × 560 and at 800 × 600 (date and reminder cards below their chips in quick add; the task popout's date, reminder and deadline cards slide over their chip row at the minimum height), Escape and a click outside closed only the card, Tab moved the keyboard in (calendar arrows + Return picked "Nov 10", typing "9am" in the reminder card wrote "9am"), and the keyboard went back to the title. iPhone 17 simulator: chips still open their popovers. Looks (glass, hover, spacing) and iPad (still popovers) need George's eyes | Opus 5.5 session, effort High |
| Sync icon in every toolbar (replaces the sidebar footer and the "…" dot), Mac toolbar + as a prominent capsule, outlined confirm button in the quick-add card | done 2026-11-01; iPhone 17 simulator checked; Mac needs George's eyes | Fable |
| Build-7 feedback: sync bolt outside the pill, two controls on every screen (Jump to today, New…, Add switch), Mac "…" with Settings, one-motion card put-away, four more themes, Spotlight-proof build paths | done 2026-11-01; iPhone 17 simulator checked; Mac needs George's eyes | Fable |
| Mac Settings page (in-window, sections, shortcuts, data, previews) | done 2026-11-01 on branch `mac-settings`; no Settings window: the sidebar gear, ⌘,, the "…" Settings… and the sync bolt select `SidebarItem.settings`; seven sections (200 pt list, ≤ 620 pt content, remembered); keyboard-shortcut table, Data counts + store size, iCloud "Last change" (no sparkline: the monitor keeps no per-day counts), 56 pt swatches + live preview, Compact rows stored (TaskRow pending), About build date / Changelog / inline What's new. Mac app run with an uncommitted demo hook (in-memory store): real clicks on the gear, bolt and "…" → Settings… opened the page; all seven sections clicked and remembered at 760 × 560 and 1200 × 800; ↓ moved sections; the ⌘, item is in the app menu, but this session's window could not become key so the shortcut itself is unverified. Views checked as rendered images, every theme. iPhone 17 simulator: the sheet has the same groups; a pre-existing overflow (8 swatches in one row) fixed with rows of four. Glass pill, hover and ⌘, need George's eyes | Opus 5.5 session, effort High |
| Build-8 feedback: bolt shapes and per-theme pastel colours, Settings page takes the whole window with Back, Flipboard add tile in the grid, Inbox priority sections, Upcoming view options (Show overdue, Days shown), Mac title field without the grey box, Mac Add task row at body size, Compact rows wired | done 2026-11-01; iPhone 17 simulator checked (Inbox sections, Flipboard tile, bolt); Mac needs George's eyes | Fable |
| Build-9/10 feedback: task rows measured to Todoist's (`ListMetrics` 12/10, titles wrap, 500-char cap, description's first line), shared header spacing (`taskSectionHeader`), no P1/P2 badge, readable Inbox priority headers, shorter iPhone "+" oval, bolt nearer the controls, Mac Settings sections in the sidebar column (sidebar stays built and fades), iPhone card fades in place with the keyboard (`KeyboardObserver`) | done 2026-11-01; iPhone 17 simulator checked (Today, Inbox, Upcoming rows and headers; card opens above the keyboard and closes after Return); Mac needs George's eyes (row insets, single header line, sidebar fade, toolbar "+" back to build 9's) | Fable |
| Build-11 feedback: flat Mac-style lists on iPhone (plain style, `completionRowBackground` on the background), snappier completions (`CompletionMotion.hold` 380 ms), toast above the island, confirm pill hollow→filled, tap-away Discard bubble + sticky drafts (`QuickAddDraftStore`, `KeyboardObserver` placement) | done 2026-11-02; iPhone 17 simulator checked (Today flat list, Discard bubble, keyboard back on tap, Discard closes); sync robustness delegated to session 25 (`sync-robustness`) | Fable |
| Completion final until Undo, toast never behind the island, popout closes on a remote delete, push handler stops waiting (brief 29) | done 2026-11-02 on branch `completion-popout-push`: a tap on a row in its completion animation does nothing (`CompletionAnimator.tap`); every iPhone toast is drawn by `PopoutHost` over the shell (`completionToast`), 16 pt above the "+" on the iPhone 16 and 17 simulators; a popout whose task is deleted elsewhere closes (store check by id, `@Query` watch + after imports; iPhone sheet closed in 20 ms, Mac panel in a hosted test); `ImportWaiter` releases the push handler as soon as its import has finished, at once if it already had | Opus 5.5 session, effort High |
| Quick-add time phrases, reminder syntax, repeat time, creation order (brief 31) | done 2026-11-03 on branch `claude/quick-add-language-f93364`: "in 10 minutes", "in two hours", "in half an hour", "in three days", "in a week" (one `.date` token; minutes and hours need "in"); `!Nm(b)`/`!Nh(b)`/`!Nd(b)`/`!0`/`!at` only, and only with a time; repeat rules store the wall-clock time ("daily;1;;;02:30", additive) and rebuild each occurrence from it, so the spring-forward drift is gone; lists break ties on creation order before the title; the suggestion row is gone; a stored card finds its Group by id after a rename and drops a deleted one. iPhone 17 simulator: "Call mum in 2 hours !15mb" lit both tokens with the Reminder chip at now + 2 h · 15 min, "Fix sink !" lit nothing, "Zebra…" then "Apple…" added seconds apart stayed in that order in Today and the Inbox | Opus 5.5 session, effort High |
| Subtasks and the task editor (brief 32) | done 2026-11-03 on branch `claude/subtasks-editor-ed7436`: schema V3 (`TaskItem.parent` / `subtasks`, optional, cascade from the parent; V2 frozen, hashes pinned), one level only, never a row of their own (Inbox, Today, search, every filter/Group/label list), completing a task completes its open sub-tasks (Undo reopens exactly those), a repeating task's roll-over reopens them, backups carry `parentID`, dedupe repairs nesting and Groups; the task popout rebuilt like Todoist's task view (title card with Group and date rows, value pills, Sub-tasks checklist with rename, reorder and delete, one-tap Confirm that saves typing and closes); quick-add "+" → Subtasks lines; rows show "2/5". iPhone 17 simulator checked as screenshots via a launch-argument hook (the simulator panel request went unanswered, so no real taps); Mac panel checked as an offscreen render. **CloudKit schema must be deployed to Production before 0.4.1** | Opus 5.5 session, effort xhigh |
| Joined highlights, earlier phrases come back (brief 37) | done 2026-11-04 on branch `claude/highlight-merge-override-0d596b`: a later date, time, priority, Group, repeat or reminder overrides the earlier one, which stays in the token list as superseded (plain title text, no effect) and applies again when the winner is tapped off; same-coloured highlights a space apart draw as one box ("[tom 4]"), split at a line wrap, one tap switches off the whole box; a reminder picked before a time is highlighted and counts once a time is set; a restored card shows the same boxes. iPhone 17 simulator (HITList-37): "test 2 [p1] [tom 4]", one tap on the box → plain "tom 4" with P1 kept; "jan 6 zach fox [in a month]" (Dec 4) → tap → "[jan 6] zach fox in a month" (Jan 6, 2027); "Ping [tom !15mb]" with the chip at 15 min before | Opus 5.5 session, effort High |
| Mac Upcoming board (brief 38) | done 2026-11-04 on branch `claude/mac-upcoming-board-8ae411`: Mac (and full-width iPad) Upcoming is a board of seven 270 pt day columns from today with Overdue first, ‹ Today › and a month title (click it for a calendar), cards are `TaskRow` (checkbox, sound, Undo toast), click opens the popout, drag a card to a day (time and repeat time kept), Overdue's Reschedule opens the date card, each day's "+ Add task" opens quick add on that day; iPhone list unchanged. Offscreen Mac render and iPad Air 13" simulator in landscape checked (arrows, Today, calendar jump, Reschedule, card → popout, add on a day, drag to a day, completion toast); Mac drag feel, scrolling and the header need George's eyes | Opus 5.5 session, effort xhigh |
| Account and profile, privacy policy (brief 34) | done 2026-11-04 on branch `claude/accounts-profile-d32a23`: schema V4 adds `Profile` (name, picture as a CKAsset, per-field times; V3 frozen, hashes pinned) and is in CloudKit Development (a fresh store imported the sample profile back); `ProfileStore` (created on the first write, every write and merge in the sync log without the name), dedupe merges two devices' profiles (newest name, newest picture, never loses one); Settings → Account first on the iPhone and the Mac (avatar via PhotosPicker or initials, name saved on Return, the iCloud state in the same words as the iCloud screen, how to sign out, Export, how to delete all data, Delete profile); `ProfileBadge` built, not placed; `docs/privacy.md` for GitHub Pages and a Privacy policy row in About; Copy diagnostics names the account state and the profile's sync. HITList-34 simulator checked (name, initials, picture, delete confirm, About link, diagnostics, a first launch without iCloud). **Deploy the CloudKit schema to Production before 0.5.0**; the Mac Account section needs George's eyes | Opus 5.5 session, effort xhigh |
| Flipboard tab, Browse and Settings behind the top-right control (brief 35) | done 2026-11-04 on branch `claude/vigorous-joliot-e36150`: iPhone tabs are Inbox · Today · Flipboard · Upcoming; the "…" on each tab's first screen is a magnifying glass ("Browse") that pushes Browse onto that tab's stack, and on Browse and the lists pushed from it a gear ("Settings") opens the Settings sheet (no second Browse); the screen's former "…" items (Review Inbox…, Jump to today, Edit Group…) sit under a divider in its view-options menu, and on the Flipboard a long press on the flip-sound button shows Add Switch… (a tap still toggles the sound); Settings… and the version left the iPhone menu; Browse has a profile row on top (`ProfileBadge`, or "Add your name"; opens Settings, Account first) and ends with Completed then Settings; Flipboard is a start screen, a stored Browse opens on Today. iPad and the Mac keep the "…". HITList-35 simulator checked (tab bar, the glass on Inbox, Flipboard, Upcoming and Today, Browse with the gear, Settings from the gear, Browse's last rows, relaunch onto Flipboard; the items reaching each view-options control confirmed by a temporary log line); the open menus and the long press need George's eyes | Opus 5.5 session, effort High |
| Taller editor, bigger Confirm, confirm by button (brief 36) | done 2026-11-04 on branch `claude/nice-lamport-d221b7`: the iPhone editor sheet opens at 561 pt instead of 451 (iPhone 17; `EditorOpeningDetent`, capped at 85% on short screens, large kept) so the title card, the pills and two sub-tasks fit with 32 pt of air above Confirm; one `ConfirmPill` for quick add and the editor (48 pt tall, 76 wide like the "+", 17 pt arrow; the Mac keeps 34 pt); the "Created …" line and the divider are gone, the dates are disabled lines at the end of the editor's "…" menu; iPhone titles show a plain return key and Return does nothing (`TitleReturn`; a paste still becomes one line; quick add's Location Return goes back to the title; sub-task lines keep Return = next; the Mac keeps Return/⌘Return); a swipe down on the editor with typing asks Discard above the footer, without typing it just closes. HITList-36 simulator checked (heights measured, keyboard key, Return in both titles, swipe with and without an edit, Discard, keep editing, the "…" menu) | Opus 5.5 session, effort High |
| Profile top-left, Flipboard rightmost (brief 40) | done 2026-11-04 on branch `claude/profile-chrome-00f2c6`: iPhone tabs are Inbox · Today · Upcoming · Flipboard again (stored start screens unchanged); the Mac and iPad sidebar starts with an account button (24 pt avatar or initials, the name or "Add your name", a small chevron) above Inbox, below the traffic lights and the sidebar toggle, opening a dropdown card in the design system's style (not an NSPopover on the Mac; a popover on iPad): Account settings… (the Mac Settings page straight at Account, `SettingsRouter.open(at:)`; the Settings sheet on iPad), Settings… (⌘,), a hairline, the iCloud state line in Settings → Account's words; a click outside or Escape closes it. iPhone Browse shows the avatar and name at the top left beside Back (the list row is gone) and opens Settings, Account first; the name gets 74 pt so the bar keeps New and the gear (a wider name shows its first word, then only the avatar; "Add name" before one is set). Offscreen Mac renders of the real sidebar (named, unnamed, open card), HITList-40 iPhone 17 (tab bar, Browse with and without a name) and HITList-40-iPad iPad Pro 11" (sidebar top) checked; the open menus by hand need George's eyes | Opus 5.5 session, effort High |

## 1. Multi-device dedupe

Problem: `TaskActions.seedDefaultsIfNeeded` seeds the four default saved filters when a per-device
UserDefaults flag is unset and the local store is empty. A second device launches before its first
CloudKit import finishes, sees an empty store, and seeds again. The same happens for projects and
labels created with the same name on two offline devices. CloudKit cannot enforce uniqueness.

Fix (Apple's recommended pattern):
- Seed with stable, deterministic UUIDs (UUIDv5 of a fixed namespace + name) so duplicates are
  detectable by `id`, not just by name.
- Run `Deduplicator.run(in:)` after every successful CloudKit import
  (`NSPersistentCloudKitContainer.eventChangedNotification`, type `.import`, succeeded) and once at
  launch. For each model type: group by `id`, then by case-insensitive trimmed `name`; keep the
  oldest `createdAt`; re-point `TaskItem.project` / `TaskItem.labels` to the survivor; delete the rest.
- Deterministic winner on every device so the pass converges instead of ping-ponging.

## 2. Versioned schema

Rules for the Production CloudKit container (additive only, forever):
- Never rename or delete a model or attribute. Never change an attribute's type.
- New attributes must be optional or have a default value. New relationships must be optional.
- No `@Attribute(.unique)`. No non-optional relationships.
- Every model change: bump `HITListSchemaV<n>`, add a lightweight migration stage, run the app once
  against Development, deploy the schema in the CloudKit dashboard, then release.
- `scripts/release.sh` refuses to upload while the Development schema differs from Production
  (needs a cktool management token; see the script header).

Implementation: `enum HITListSchemaV1: VersionedSchema` wrapping the current models,
`HITListMigrationPlan: SchemaMigrationPlan`, container built from the plan.

## 3. App Group store

Widgets, Shortcuts/App Intents, and a Share extension need the store in a shared container.
Moving it later means a migration for every user; today the data is throwaway.
- App Group `group.com.trammells.hitlist` on both platforms (macOS requires the team-id prefix
  form `UC8N98H3RT.com.trammells.hitlist` for the entitlement value; iOS uses `group.` form).
- `ModelConfiguration(url:)` pointing at `containerURL(forSecurityApplicationGroupIdentifier:)`
  /`HITList.store`. One-time move of an existing local store file if present.
- UserDefaults for shared settings via `UserDefaults(suiteName:)`.

## 4. Git + release script

`scripts/release.sh` bumps the build number, regenerates the project, runs the core tests, archives
and exports iOS and macOS, verifies the entitlements, uploads both with altool, commits and tags.
Run `scripts/release.sh --help`.

## 5. Sync resilience

- Observe `CKAccountChanged`; when the account changes or signs out, the system wipes the local
  mirror. Show a clear state in Settings and in the sidebar rather than an empty list.
- Settings → "Reset local cache and re-download": delete the store files, rebuild the container,
  let CloudKit re-import. Confirmation dialog, explain the data is safe in iCloud.
- Automatic JSON snapshot once a day into the app's iCloud Drive Documents folder (keep last 14).
  Manual Export/Import already exist (`SnapshotBuilder`, `SnapshotDocument`).
- Sync status row: "Synced 2 min ago", "Syncing…", "Offline", "Not signed in to iCloud",
  with the raw last error behind a disclosure.

## 6. Reminder robustness

- `NotificationScheduler.reschedule` runs only on scene activation. Also run it after each
  successful CloudKit import (the app already has the `remote-notification` background mode).
- Notification category with Complete and Snooze 1h actions.
- Reschedule on `NSSystemTimeZoneDidChange` and `significantTimeChange`.
- Respect the 64 pending-notification cap explicitly (sort by due date, truncate).

## 7. Tests + CI

- `HITListTests` target: in-memory `ModelContainer`; cover completing recurring tasks,
  reschedule, snapshot round-trip, dedupe convergence, seeding idempotence.
- Xcode Cloud workflow: test on push, archive + TestFlight on tag.

## 8. Calendar, themes, preferences

EventKit read-only overlay of today's events; theme choices within the dark palette; filter
defaults. UI sessions own these.

## Task Flipboard (shipped 2026-10-28; start-red and flip sound 2026-10-31; charging and long-press menu 2026-10-31)

A Flipboard screen (sidebar, under Upcoming) shows recurring chores as a wall of skeuomorphic
rocker switches: green while the task is due in the future, red once it is due or overdue (the LED
glows, and pulses slowly when overdue unless Reduce Motion is on), with a thin light bar and
"2 of 3 days" for time elapsed in the interval. Red sorts first, most overdue on top. Tapping a red
switch flips it with a sprung 3D rocker animation, a haptic and a light-switch click (`flip.caf`,
110 ms, synthesised; "Flip Sound" toggle in the board's … menu, on by default, silent switch respected)
and completes the task
through `TaskActions.toggleCompletion`; like a physical switch, the flip then restarts the interval
from the flip day (George's decision, 2026-10-28), so a 3-day switch flipped on Thursday is due
Sunday. A new switch starts red with "Flip to start" and an empty light bar (it is due the day it is
created; George's call, 2026-10-31): "Shave" every 2 weeks is red, a flip makes it green for 14 days,
then it is red until flipped again. "Add to Flipboard" makes a task without a future due date due
today (red); one due in the future keeps that day (green). A green switch asks before being done early. A switch is just a recurring task without a time that carries the
`flipboard` label (stable seeded id), so there is no schema change and a real board could later be
driven from the same records. Add switches with "+" (title, every N days/weeks, flips per interval)
or "Add to Flipboard" in task detail. Code: `HITList/Views/Flipboard/`, tests in
`HITListTests/FlipboardTests.swift` (`FlipboardTests` and `FlipboardRulesTests`). Not yet built from
the original idea: widgets.

**Long-press menu and the lamp (2026-10-31).** A long press anywhere on a switch, the rocker included,
opens its menu on iPhone (soft haptic as the hold registers; the rocker is no longer a `Button`, so
it no longer swallows the press); right-click opens it on the Mac and a long press there opens the
same items in a popover. Items: Flip back to red (undoes the last flip: a green switch turns red, due
on the day it was flipped since the old due date isn't stored; a charging switch loses one flip;
disabled when red with nothing counted), Edit interval…, Flips per interval…, Open task, Mark done,
Remove from Flipboard. A plain tap still flips. A green switch's LED now glows a faint green with a
soft halo (flaring once as it turns green) instead of going dark; red and the overdue breathing are
unchanged; Reduce Motion drops the breathing and the flare.

**Charging switches (2026-10-31).** `TaskItem.flipTarget` > 1 (schema V2, 1 to 10) makes a switch
need that many flips per interval: "Gym", 3 flips a week. While red each flip adds one to
`flipCount` (the first sets `flipPeriodStart`) and clicks; the flip that reaches the target charges
it, moving the due date exactly as a single flip does, with the count left at the target so the
lamps read full. When the date rule turns it red again, a `flipPeriodStart` from before the interval
being counted is stale and reads as 0 (for an overdue charger that interval is the due day moved on
by whole intervals, so last week's flips don't count this week); the next flip starts afresh. Extra
flips while charged only bounce the rocker; Mark done charges at once; lowering the target to what is
already counted charges it; editing the interval of a red charger leaves its due date alone. A
target of 1 follows the same rules and behaves exactly as before. Look: a row of lamps across the top
of the tile replaces the LED; each flip pops the next lamp on with a glow that spreads to its
neighbours; the last flip snaps the rocker green, blooms along the row and plays `bubble.caf` after
the click (both follow the Flip Sound toggle); the lamps drain right to left the first time the board
shows the next interval (remembered per device in `AppGroup.defaults`, `flipboard.shownFull`).
Captions: "2 of 3 this week" while charging, "Done this week" when charged ("today", "these 2
weeks", "this round" for other rules). The editor (now `HITSheetChrome`, with a −/+ stepper and
`HITSegmented`) has "Flips per interval" and a live preview tile whose rocker can be flipped to try
the lamps.

## External TestFlight / App Store prerequisites

Privacy policy URL (even with zero data collection), support URL, screenshots per platform,
age rating, first external build passes Beta App Review (~1 day). No code required.

## Ideas backlog (George, 2026-10-28)

Not scheduled. Each becomes a roadmap item when picked up.

- **Completion delight.** Todoist's completion sound, strike-through and the row sliding away. A
  short custom sound (respecting silent mode), haptic on iOS, 250 ms strike + collapse animation,
  undo toast for 5 s.
- **Chargeable tasks** ("gym 3x week"). A quota per period rather than a due date: `n` ticks per
  week/month, shown as a persistent card between Today and Overdue with a progress ring until the
  quota is met, then it rests until the period rolls over. Schema: new optional fields on
  `TaskItem` (`quotaCount`, `quotaPeriod`, `quotaTicks: [Date]`), so a V2 schema version.
- **AI / API / MCP.** First-class Claude integration: an MCP server exposing tasks, filters and
  quick-add (so Claude Desktop / Claude Code can read and add tasks), App Intents for Siri and
  Shortcuts, and a documented JSON export. Possibly a local HTTP endpoint on the Mac for automation.
- **Fun.** Nyan Cat very rarely flying across the top of the window; seasonal pixel-art variants of
  a few buttons on the solstices, Halloween and similar; all behind a "Delight" toggle in Settings.

## Decisions log

- 2026-10-26: iCloud private database only; home server stays a design relic (DESIGN.md).
- 2026-10-26: CloudKit.framework linked explicitly (macOS 26 sandbox bug, Apple forums 835400).
- 2026-10-26: `com.apple.developer.icloud-container-development-container-identifiers` must never be
  in the entitlements; App Store Connect rejects uploads carrying it (errors 90045 / 90285).
- 2026-10-28: Filter language skips Todoist's collaboration terms (`assigned`, `added by`, `shared`,
  `workspace`), `subtask`, `/sections` and `deadline:`: HITList is single-user and had no sub-tasks,
  sections or deadlines, so they get explanatory errors instead (sub-tasks arrived in 0.4.1, brief 32,
  but never as rows of their own, so the filter term stays out). `,` stays an AND (one list per view)
  rather than Todoist's "separate lists".
- 2026-10-31 (round 3): "Group" is the user-facing word for Project; the model and `#name`/`project:` syntax
  stay. Inbox = every dated task plus undated tasks with no Group; undated tasks in a Group show only inside
  it (notes). Today and Inbox sort priority-then-due; saved filters keep due-then-priority. Due colours:
  today green, tomorrow orange, later purple, overdue red (`HITColor.due`). Inter ships as six static 18 pt
  cuts because iOS resolves only a variable font's default instance by PostScript name.
- 2026-10-31: schema V2 deployed to CloudKit Production by George after the Development push; build 5 (0.1.0) is the first build that writes the new fields.
