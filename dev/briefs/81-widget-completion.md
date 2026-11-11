# Brief 81: complete a task from a widget, and widgets that stay true (session `widget-completion`, effort xhigh)

George, 2026-11-11, on 0.9.1:

> As for Widgets, they need to have robust cloud sync and should definitely allow for task completion within the
> widget. It can be slow (Todoist's widgets are pretty slow to update; when I check off a task, it takes 5+ seconds to
> register/disappear/get repalced with a new task, but it does at least show that it's checked), so speed isn't
> important, but it should be reliable. In general, Todoist seems to take the stance that a checked task doesn't
> complete/disappear until it properly syncs to iCloud, which is a very good approach; it properly prioritizes data
> resilience over user experience. We should adopt that mentality as well.

Read `dev/briefs/COMMON.md` (Round 18 block first), `dev/briefs/ROUND-18.md`, `74-widgets.md` (how the widgets get
their data: a snapshot the app writes into the App Group; the extension never opens the store, and that stays),
`78-steady-bolt.md` (what the app knows about a sync finishing, stalling and recovering), then
`HITListWidgets/*`, `HITList/Services/Widgets/*`, core's widget snapshot and rules, and
`HITList/Services/Intents/TaskEntity.swift` (`CompleteTaskIntent`, Siri's).

## The principle (George's; when a choice is unclear, choose by it)
Data resilience over speed. A tap is never lost. The widget never claims more than is true. A checked task stays
on the widget, shown as checked, until its completion has reached iCloud; only then does it leave and the next
task take its place. Slow is fine. Wrong is not.

## The rules
1. **A tap checks the row at once and is written down before anything else.** The widget's button runs an app
   intent that first records the request durably in the App Group (an outbox: task id, what was asked, when, a
   request id), then reloads the widget, which draws that row checked ("pending"). From this point the tap
   survives the app being killed, a crash, a reboot, a full disk error being the only excuse.
2. **The app does the completing, through the paths it already has** (`TaskActions.toggleCompletion`,
   `Flipboard.completeRow` and `flip`: a repeating task rolls on, a switch flips, sub-tasks follow, reminders are
   rescheduled, Spotlight and the badge update). Find the supported way for a widget's intent to run in the app's
   process on iPhone, iPad and the Mac without bringing the app forward (read the App Intents documentation in the
   Xcode 27.2 SDK before choosing; an intent type present in both targets, and the protocols meant for running in
   the app, behave differently per platform), and prove which process ran it on each. If on some platform the app
   cannot be reached from the widget, the outbox entry waits and the app applies it the next time it runs for any
   reason (launch, a push, background refresh): never apply it from the extension.
3. **Applied is not done.** After the app has completed the task in the store, the row stays checked on the widget
   until the export that carries that save has finished (`CloudSyncMonitor`'s export events after the save; read
   brief 78's notes for `state` against `rawState`). Then the app rewrites the snapshot without it and the widget
   shows what is next. With iCloud off or signed out (a local-only store) "saved" is the finish line. While sync is
   stuck, offline or retrying, the row stays checked and the widget says so in a quiet line ("Waiting for iCloud"),
   not an alarm.
4. **Idempotent and ordered.** A request applies once however many times it is delivered (the request id), a
   request for a task that is already completed, deleted or changed elsewhere resolves quietly (it leaves the
   outbox with a line in the sync log), and two taps on two rows both land. A second tap on a checked row does
   nothing (no un-checking from the widget: Undo is in the app, as §7 says).
5. **The Flipboard widget flips.** A tap on a red switch's pill flips it by the same road and the same waiting.
   A green pill does nothing.
6. **Widgets that stay true without being asked ("robust cloud sync").** A change made on another device must
   reach this device's widgets while the app is closed, as well as iOS and macOS allow: the silent push that wakes
   the app for an import must end in a fresh snapshot and a reload (trace it; brief 74 wired saves and imports),
   and add a background refresh task that lets CloudKit import, rewrites the snapshot and reloads, registered the
   way each platform supports. The snapshot carries when it was written and what sync state it was written in; a
   widget whose snapshot is older than a day says so quietly ("As of yesterday") instead of pretending.
7. **Honest when it cannot work.** No snapshot yet, the app never opened on this build, the App Group unreadable:
   the widget says what to do ("Open HITList once"), never an empty box.

## Items (one commit each, failing test first where there is logic)
1. **The outbox** (core model + file in the App Group, written atomically; a side store has its own) and its
   tests: durability, idempotence, ordering, a damaged file.
2. **The intent and its road into the app**, per platform, with the proof of which process ran it.
3. **Applying**: the app drains the outbox at launch, on activation, after an import and when the intent arrives;
   pending and "waiting for iCloud" states in the snapshot; leaving on the export's finish; the local-only case;
   tests with a fake monitor for every ending (exported, offline for an hour, stuck, task gone, app killed between
   the tap and the apply, killed between the apply and the export).
4. **The widgets**: the checkbox in Today and Upcoming (every size that shows rows; a row's tap target is at least
   the system's minimum, and tapping the title still opens the task), the pending look (the app's own completed
   check and struck title, dimmed), the quiet waiting line; the Flipboard's pills.
5. **Staying true**: the push path traced and fixed where it drops, the background refresh, the snapshot's age.
6. **Seen working**: extend the Home Screen UI test (it adds the widgets through SpringBoard) to tap a checkbox on
   the Today widget and watch the row go checked and then leave, with the app not running beforehand; and the same
   on a Debug Mac build as far as you can drive it. Say exactly what you could not see.

## Ownership
`HITListWidgets/*`, `HITList/Services/Widgets/*`, core's widget snapshot and rule files and a new outbox file,
`HITList/Services/Intents/*` (the completion intent's road; keep Siri's intents working), `HITList/HITListApp.swift`
and `HITList/Services/Sync/SyncAppDelegate.swift` (the lines that register background work and drain the outbox),
`HITList/Services/CloudSyncMonitor.swift` (only what you need to learn that the export after a given save finished:
add, do not change what brief 78 built), `project.yml` (background task identifiers and modes, the intent's files in
both targets; brief 80 edits the same file elsewhere), their tests (`Widget*Tests`, `IntentsTests`),
`HITListUITests/WidgetsUITests.swift`.
Not yours: the models and schema (no schema change this round: the outbox is a file, not a model), `TaskActions`
and `Flipboard` rules (call them), `Views/Companions/*`, `Support/Companions/*` (79), `Services/Weather/*`,
`DelightSettingsSection`, the app's entitlements (80), the app's own lists (their completion stays as it is: the
Undo toast is the app's answer), `dev/ROADMAP.md`, `CHANGELOG.md`, `WhatsNew.swift`, `scripts/`.

## Done
A table: every ending in item 3, what the widget shows at each moment, and the test that pins it. The proof of
which process runs the intent on iPhone and on the Mac. The Home Screen recording or frames of a tap to checked to
gone. What still depends on iOS or macOS giving the app time in the background, in plain words George can repeat to
a friend. A Release archive and export of both platforms still pass (no upload). All three suites green.
