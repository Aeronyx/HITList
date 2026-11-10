# Brief 74: widgets on iPhone, iPad and the Mac (session `widgets`, effort xhigh)

George, 2026-11-10, starting 0.9.1:

> For Mac and iOS, we should have simple Today and Upcoming widgets (along with any other obvious additions) which
> showcase a few tasks and a little calendar respectively. I'm sure we'll iterate on these after seeing them and using
> them, but we need to have them first to give feedback on them. Please implement Widgets!

Read `dev/briefs/COMMON.md` (Round 17 block first), `dev/briefs/ROUND-17.md`, `dev/briefs/HIG-NOTES.md`, the design
system README (`HITList/Support/DesignSystem/README.md`) and `project.yml`. This is the app's first extension: the
store was moved into the App Group on 2026-10-27 for exactly this (`HITList/Support/AppGroup.swift`: iOS
`group.com.trammells.hitlist`, macOS the team-prefixed `UC8N98H3RT.com.trammells.hitlist`, and why they differ).

## How the widgets get their data (decided; say so if you find a reason it cannot work)
- **The extension never opens the store.** The store mirrors to CloudKit; a second process must not touch it. The
  app writes a small JSON snapshot into the App Group container after every save and every finished import
  (debounced), then asks WidgetKit to reload. The extension reads that file and nothing else.
- **The snapshot holds tasks, not finished lists**, so a widget is right at 00:01 without the app running: each
  open task's id, title, priority, due date and time flag, Group name and colour, label names, repeat flag, switch
  facts (member, opted in, board id), plus the Switchboards (name, cadence, reset time, weekday). The extension links
  `HITListCore` and asks the same rules the app asks (`TaskOrdering.isInToday`, `FlipboardSwitch`,
  `SwitchboardSchedule`, `UpcomingSchedule`'s day rules): never a second copy of a rule. Put the snapshot's model
  and the pure "what does this widget show at time T" functions in core, with tests around midnight and a board's
  reset. Timeline entries at the next midnight, the next reset and each shown task's due time.
- **A side store has its own snapshot** (`HITLIST_STORE_SUFFIX`), so a Debug run never feeds George's real widgets.
- **No completing from the widget in this brief.** A tap opens the app: a task's row opens that task, the rest of
  the widget opens its screen. That needs the app's first URL scheme (`hitlist://task/<id>`, `hitlist://today`,
  `hitlist://upcoming`, `hitlist://flipboard`) and one `onOpenURL` that routes through `IntentRouter` like Siri's
  intents do. Leave the row views ready for a button later; George will ask for it once he has used them.

## The widgets (the app's own look: slate theme from the chosen palette, Inter through `HITType`, no default styling)
1. **Today**: small, medium, large. "Today", the count, then the rows Today shows in its order: the priority ring in
   the task's colour, the title, and under it the time or Group as the row's second line does. Small: two or three
   titles. Medium: four or five. Large: Overdue and today as the list has them. Nothing due: one calm line, not an
   empty box.
2. **Upcoming**: medium and large (a small one only if it reads well). A little calendar and the next tasks: the
   week from today as a strip with a dot under each day that has tasks (the week starts on Settings' day), today
   marked the way the app's `HITCalendar` marks it, then the next days' tasks under their day. Large: the month
   grid with dots, then the next few tasks.
3. **Flipboard**: small and medium. The board as a status check: each switch a small green or red pill with its
   name, loose switches or one Switchboard chosen in the widget's settings (an app-intent configuration), with the
   board's line ("Daily · resets 4:00 AM · 2 of 4"). Red and green exactly as the board judges them at that minute.
4. **Lock Screen (iPhone), only if 1–3 are finished and good**: circular (today's count), rectangular (the next two
   tasks), inline ("3 tasks today"). `privacySensitive` where titles show.

## Items (one commit each, failing test first where there is logic)
1. **The target.** A widget extension for iOS and macOS in `project.yml` (XcodeGen; `HITListWidgets/` for its
   sources), embedded in the app, sandboxed, with the App Group in each platform's form, the Inter cuts, and the
   design-system files it needs compiled in (share source files; do not copy them). `scripts/release.sh` reads
   exactly one `MARKETING_VERSION` line and one `CURRENT_PROJECT_VERSION` line from `project.yml` and the extension's
   version must equal the app's: move those two lines to the project-level settings so both targets inherit them, and
   give the extension no version line of its own. Prove a Release archive of both platforms still builds and exports
   (`xcodebuild archive` and `-exportArchive` with `ExportOptions.plist`, as the script does, without uploading);
   paste the entitlements of the exported extension in your report.
2. **The snapshot**: core model and rules with tests; the app's writer (`Services/Widgets/`), started from
   `HITListApp` in one line; reloads after saves, imports, a theme change and the week-start setting.
3. **Deep links**: the URL scheme, `onOpenURL`, the routes, tests.
4. **Today**, 5. **Upcoming**, 6. **Flipboard**, 7. **Lock Screen** (see above), each with a hosted test that
   renders every family offscreen at its exact size on demo data (`ImageRenderer`), kept as screenshots.
8. **A way to see them.** Settings → About or the design-system gallery gets nothing new; instead say in the report
   exactly how George adds each widget on the iPhone and the Mac, and try to capture the real widgets on the
   simulator's Home Screen (XCUITest can drive SpringBoard's widget gallery; if it costs more than an hour, stop and
   send the offscreen renders).

## Ownership
New `HITListWidgets/*`, new `HITList/Services/Widgets/*`, new `HITList/Services/DeepLinks/*`, new core files for
the snapshot and its rules (+ tests), `project.yml` (the new target, the two version lines, the URL scheme, the
extension's entitlements files), one line each in `HITList/HITListApp.swift` (start the writer; `onOpenURL`) and in
`IntentRouter` if a route is missing, new `HITListTests/Widget*Tests.swift`, a UI test file of your own if you
drive SpringBoard.
Not yours: `scripts/` (tell the supervisor what `release.sh` should also verify), the models and schema (no schema
change this round), `Views/Flipboard/*`, `TaskRow`, the list views, `Upcoming/*` (77), the popouts and design-system
styles (75: compile them in, do not edit them), `Views/Companions/*` (76), `dev/ROADMAP.md`, `CHANGELOG.md`,
`WhatsNew.swift`.

## Done
Every family of every widget rendered on demo data, iPhone and Mac sizes, in one contact sheet per widget; the real
widgets on a simulator Home Screen if you got there; the archive and export proof; what an Xcode-automatic signing
run registered in George's developer account (new App IDs, capabilities), since those are permanent. All three
suites green.
