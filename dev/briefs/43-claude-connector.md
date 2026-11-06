# Brief 43: a Claude connector (branch `claude-connector`, effort xhigh)

Read `briefs/COMMON.md` first. Six sessions run at the same time; see COMMON's "Round 10 ownership".

George's backburner note, 2026-11-04:

> A very clean, robust Claude integration/connector/whatever is best, with an option so either Claude can see all
> your tasks and you pick the ones it can't, or so Claude can see none of your tasks until you tag the ones it can.
> A full AI integration framework for clean interactions with JSON exports, MCP servers, etc. would be great, but
> keep it lightweight.

## The design (proposed; settle it in your first hour, write the choice and why into the report)

- **An MCP server that Claude Desktop and Claude Code launch over stdio**, shipped inside the Mac app as a small
  command-line helper (`HITList.app/Contents/MacOS/hitlist-mcp` or `Contents/Helpers/`), a new target in
  `project.yml`. The helper never opens the SwiftData store itself (a second process writing to the store while
  CloudKit mirrors it is how stores get damaged). It talks to the running app over a local channel, and every read
  and write goes through the app's main context and `TaskActions`. Candidates: a loopback-only HTTP listener in the
  app (`Network.framework` `NWListener` on 127.0.0.1, needs `com.apple.security.network.server` in the Mac
  entitlements) with a random bearer token in the shared app-group container; or XPC through the app group. Pick the
  one that works sandboxed under TestFlight; justify it. If the app is not running, the helper says so in the tool
  result ("Open HITList on this Mac").
- **Privacy modes** (Settings → Claude, new section on both platforms; the iPhone shows only the setting and the
  export, since Claude's apps cannot launch a local server there): "Claude sees all tasks except those labelled
  `@private`" or "Claude sees only tasks labelled `@claude`" (label names editable). Use labels, so no schema change.
  A Group can carry the rule too if it is a small step (all tasks in a Group labelled …), otherwise leave it out.
  Hidden tasks are invisible to every tool: not listed, not countable, not completable, not searchable. Off by default
  until George turns it on; a master switch "Allow Claude" (off = the helper gets "HITList's Claude access is off").
- **Tools** (small and sharp): `list_tasks` (a filter query in HITList's filter language, e.g. "today | overdue",
  default open tasks, limit), `get_task`, `add_task` (quick-add text, parsed exactly as the app does, plus optional
  description), `complete_task`, `update_task` (title, description, due via quick-add date phrase, priority,
  labels, Group), `list_groups`, `list_labels`. Task ids are the stable ids the snapshot JSON already uses. Every
  write is logged in the sync log under a `claude` kind (never task text) and shows the usual Undo toast in the app
  where possible.
- **JSON export for any AI**: "Copy for Claude" / share sheet on both platforms that exports only the tasks the
  privacy mode allows, in the existing snapshot JSON shape, plus a one-paragraph schema note.
- **Setup**: Settings → Claude on the Mac shows the exact Claude Desktop config snippet (`claude_desktop_config.json`
  `mcpServers` entry with the helper's path) and the `claude mcp add` command for Claude Code, each with a Copy
  button, and a "Test connection" row. Write the same steps as `docs/claude.md` (GitHub Pages) for friends.

## Items (one commit each, failing test first where there is logic)
1. Privacy filter in HITListCore or app code (pure, test-first): mode × labels → visible task set; hidden tasks
   unreachable by id.
2. The app-side endpoint and token (Mac), with tests for auth (no token, wrong token, loopback only).
3. The helper target: MCP stdio JSON-RPC (initialize, tools/list, tools/call), no third-party dependencies; tests
   for message framing and each tool against an in-memory container through the app-side handler.
4. Settings → Claude (new `Views/Settings/ClaudeSettingsSection.swift`, one line in `SettingsView.swift`, one entry in
   the Mac section list `MacSettingsSection.swift`), JSON export, `docs/claude.md`.
5. End-to-end on this Mac: build the Debug Mac app, run it with its own store suffix (never the real store), call the
   helper by piping JSON-RPC into it (`initialize`, `tools/list`, `list_tasks`, `add_task`, `complete_task`) and paste
   the transcript in the report. Quit the Debug app afterwards.

## Ownership
New `HITList/Services/Claude/*`, new helper target sources (e.g. `HITListMCP/`), `project.yml` (the new target and
its files; regenerate), `HITList/HITList-macOS.entitlements` (only the entitlement the chosen channel needs; never
the CloudKit development-container key), new `Views/Settings/ClaudeSettingsSection.swift`, one line in
`SettingsView.swift`, the Claude entry in `Views/Settings/Mac/MacSettingsSection.swift`, `docs/claude.md`; tests:
new `ClaudeConnectorTests` (+ core tests if the filter lives there); ROADMAP row "Claude connector (brief 43)".
Not yours: `TaskActions.swift` (call it; if it lacks an entry point you need, add it in a new extension file of yours),
`SettingsRouter.swift` (40), anything Sync or Profile (42).

## Done
All three suites green; the end-to-end transcript; screenshots of Settings → Claude on the iPhone simulator; the
report gives George the exact steps to connect Claude Desktop and Claude Code, and what the entitlement change means
for App Review (one sentence).
