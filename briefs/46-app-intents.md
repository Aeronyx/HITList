# Brief 46: Siri, Shortcuts and Spotlight through App Intents (branch `app-intents`, effort High)

Read `briefs/COMMON.md` first. Briefs 39, 40, 43, 45 are still running and 41, 42, 44 are merged; see COMMON's
"Round 10 ownership". You touch only new files plus the ones listed below.

From `ROADMAP.md` ("AI / API / MCP": "App Intents for Siri and Shortcuts") and George's note on 2026-11-04 asking for
a clean, lightweight AI integration (brief 43 does the Claude MCP side; this is Apple's side).

## Items (one commit each, failing test first where there is logic)
1. **Add Task intent** (`AddTaskIntent`): one text parameter, parsed by the same quick-add parser and
   `TaskActions.create` as the card ("Buy milk tom 5pm p1 #Home"), optional Group; returns a short dialog
   ("Added ‘Buy milk’ for tomorrow 17:00"). Works from Siri, Shortcuts and the Action button, without opening the app
   (`openAppWhenRun = false`), writing through the shared model container (the app's `ModelContainerFactory`, the same
   store and CloudKit mirroring; never a second container on the same store at the same time: read how the app
   builds its container and reuse it).
2. **Show / open intents**: "Open Today", "Open Inbox", "Open Upcoming" (`OpenIntent`/deep link into the right tab or
   sidebar item), and **Today's tasks** returning a list snippet (titles and times, overdue first) for Siri.
3. **Complete Task intent** with a `TaskEntity` (`AppEntity` + `EntityQuery` with string search over open tasks,
   sub-tasks excluded), so Shortcuts can pick a task; completing goes through `TaskActions.toggleCompletion`.
4. **AppShortcutsProvider** with natural phrases ("Add a task in HITList", "What's on my HITList today") and a
   short-title per shortcut; Spotlight indexing of the `TaskEntity` only if it is a one-liner (`IndexedEntity`),
   otherwise leave it.
5. **Privacy**: if brief 43's Claude privacy labels exist on master when you finish, ignore them (Siri is the user,
   not an AI reading the list). Say so in the report.

## Ownership
New `HITList/Services/Intents/*`; `HITListApp.swift` only if the shortcuts provider or a deep-link handler needs one
line there (say so); a deep-link entry point in a new file of yours (do not edit `ContentView`, `MobileShell` (45),
`SidebarView` (40)): if routing needs a change in those, report the exact lines; tests new `IntentsTests`;
`project.yml` only to add files; ROADMAP row "Siri and Shortcuts (brief 46)".

## Done
All three suites green; the Add Task intent run from a test against an in-memory container; screenshots from your own
simulator of the Shortcuts app listing HITList's actions (and a run of Add Task if the simulator allows it); the report
lists the Siri phrases for George.
