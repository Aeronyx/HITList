# 159: the privacy and security review's findings, fixed (code)

Round 32's review 155. Its report is in the notes folder: `round-32/155-privacy-security-review/REPORT.md`. Each fix
with a test written first and seen to fail, where a test can reach it.

**Yours**: `HITList/Services/Share/ShareInbox.swift`, `HITList/Services/Widgets/WidgetCompletionCenter.swift`,
`HITList/Services/NotificationScheduler.swift` (its log lines only), `HITList/Views/Settings/SyncLogView.swift`,
core's `MCPServer.swift` and `ClaudeTools.swift`, `HITList/Services/Claude/ClaudeToolHandler.swift`,
`HITList/PrivacyInfo.xcprivacy`, the location usage string in `project.yml` (that line only, then `xcodegen
generate`) and `HITList/Services/Weather/WeatherSettingsText.swift`, `HITList/Services/CloudSyncMonitor.swift` (the
two lines that log the store's path, 311 and 356, only), `docs/privacy.md`. **Not yours**: `scripts/release.sh`,
`BetaFeedback.swift` (the supervisor's, with George), `TaskActions.swift` and core's `ClaudeAccess.swift` (agent 157
takes finding 2), `LocalBackup.swift` (agent 156), anything under `SyncEngine/`.

1. **Titles and Group names in the sync log and, public, in the system log** (finding 1): every line names an item
   by its kind and the first eight characters of its id, never its words (`SyncLog.swift`'s promise and
   `docs/privacy.md`'s); the morning summary's body leaves the scheduler's line; the copy of the log made for the
   share sheet is removed when the sheet closes. A test that walks the log's lines after a share and a widget
   completion and finds no title.
2. **`update_task` overwrites with no undo and calls itself non-destructive** (finding 3): the destructive hint true
   for the tools that change or complete; clearing a description that is not empty needs an explicit argument that
   says so; say what else you did and why no more.
3. **The privacy manifest lacks two required-reason categories** (finding 4): file timestamps (C617.1) and system
   boot time (35F9.1), for every target that calls them (the widget and share extensions copy the app's manifest:
   check what each really calls).
4. **The location prompt says "never stored or shared" while the location goes to Apple's weather and map
   services** (finding 7): true words, as short.
5. **The Mac user's short name in logs a person sends** (finding 8): the store's path from `/Library/` on.

Proof: core `swift test`; the Mac's hosted tests for the classes you touched and the whole of `HITListTests` once at
the end (`-derivedDataPath build.noindex/159`); `plutil -lint` on the manifest and a look at the built app's copy.
