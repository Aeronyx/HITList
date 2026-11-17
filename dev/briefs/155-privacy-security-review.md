# 155: what leaves the device, what can get in, and what the app is entitled to (read-only review)

Before a real launch. HITList holds a person's whole to-do list; it talks to iCloud, to a weather service, to
Claude when the person connects it, to a share extension and widgets, and it answers deep links and a local MCP
helper. Review it as the person who would have to answer for a leak.

Read: `HITList/Services/Claude/`, core's `ClaudeAccess.swift`, `ClaudeTools.swift`, `ClaudeWire.swift`,
`ClaudeHelperBridge.swift`, `MCPServer.swift`, `HITListMCP/`; `HITList/Services/DeepLinks/`;
`HITList/Services/Share/`, `HITListShare/`; `HITList/Services/Weather/`; `HITList/Services/Sharing/` (Shared
Tasks: a second CloudKit container other people's devices write to); `HITList/Services/Sync/SyncLog*.swift` (a log
a person is asked to send); `HITList/Services/Spotlight/`, `Notifications/`, `Calendar/`; the entitlements of every
target (`project.yml`, `HITList/*.entitlements`, the extensions'), `HITList/Info.plist`,
`HITList/PrivacyInfo.xcprivacy`.

Answer each with findings or "looked, nothing":

1. **What leaves the device, to whom, and whether the person was told.** Every network call: the host, what is in
   the request (a location, at what precision? task text? an identifier?), whether it happens before the person
   asked for the feature. The weather: which service, what location is sent, what happens when the answer is no.
2. **Claude and the MCP helper**: who can connect to the local endpoint (another user on the Mac, another app, a web
   page through the browser: the origin, the port, the token, where the token is kept and how it is compared);
   what a connected client can read and change, and whether a destructive tool (delete, bulk change) is bounded and
   undoable; whether text in a task (which another person can put there through Shared Tasks or a share sheet) can
   steer a tool call; `ClaudeAccess`'s rules against what the handler really enforces.
3. **Everything that comes in from outside is data**: deep links (`hitlist://…`: can a link delete, complete or
   change something without a tap; can it open a state that crashes?), the share extension's input, a Todoist
   archive (zip paths that climb out of the folder, a zip bomb), a backup file chosen for restore, a shared task
   from another person (lengths, counts, a flood), pasted text.
4. **Logs and files a person may send or lose**: every `privacy: .public` on a value that can hold a title, a note,
   a name, a place or an address; the sync log file (what it holds, where it lives, how long); backups and exports
   at rest (their file protection, whether they are in a place iCloud Drive or a Mac backup copies); temporary files
   left behind; the pasteboard; screenshots in the app switcher.
5. **Entitlements, Info.plist and the privacy manifest**: each entitlement of each target needed and no more; each
   usage string true and plain; `PrivacyInfo.xcprivacy` listing the required-reason APIs the code really calls
   (`UserDefaults`, file timestamps, system boot time, disk space) and nothing it does not; App Transport Security;
   the app group shared by the widget and share extension (can either read more than it needs?).
6. **Secrets**: nothing secret in the repository, the bundle, the Info.plist or a log (keys, tokens, George's
   address). Report a find by its place only; never copy a secret's value into your notes or your report.

Write `FINDINGS.md` in your notes folder, and report as the Round 32 block of `dev/briefs/COMMON.md` says.
