# 166: nothing that identifies a person in the repository's files (code)

George, 2026-11-18: "remove any identifying information from the repository." The repository is public. This brief
is the **files as they are on master**; the history and the commits' author lines are the supervisor's question to
him and not yours: rewrite no history, push nothing.

**What counts**: an e-mail address of a real person; a surname or full name; a home folder's path
(`/Users/<name>/…`); a device's identifier (a phone's UDID) or its given name; a tester's or friend's name, address
or anything from their feedback or crash reports; an App Store Connect key id, issuer id or any credential (there
should be none: if you find one, stop and put it at the top of your report, never in a commit message); a street,
town or coordinates that are his; a real task's title copied from his data into a document or a test.
**What stays, and is listed in your report as staying, with why**: the bundle identifiers, App Group and iCloud
container names (`com.trammells.hitlist…`: they are the app's identity in TestFlight and iCloud and cannot change
without making a new app and stranding every tester's data), the team id where signing needs it, the first name
"George" in `dev/` and `CLAUDE.md` (about nine hundred places; say how many and leave them: the supervisor asks
him), the GitHub owner's handle in URLs.

**Yours**: every tracked file, for these replacements only; `HITList/Views/Account/BetaFeedback.swift` and its
tests; `project.yml`; a new tracked `Config/` folder; `.gitignore`; `scripts/release.sh` **for the one check named
below and nothing else**; `README.md`. Other agents are editing the app's Swift files at the same time: outside
`BetaFeedback.swift` and its tests you change no Swift file except to replace an identifying string inside a
comment or a test's fixture, one small hunk each.

1. **Find everything first** and list it in your notes folder (not in the repository): `git grep` for the address,
   the surname in any case, the home path, the UDID, `@` addresses in general, "UDID", "iPhone 16" names, key ids;
   read `dev/SUPERVISOR.md`, `dev/briefs/COMMON.md` and `README.md` whole; skim the briefs' matches.
2. **The feedback address leaves the source.** Send Beta Feedback writes to an address that is in the code today.
   It becomes a build setting read from the app's Info.plist: a tracked `Config/HITList.xcconfig` that sets
   `HIT_FEEDBACK_ADDRESS =` to nothing and ends with `#include? "Local.xcconfig"`; an untracked, git-ignored
   `Config/Local.xcconfig` that sets it on this Mac (create it here with the address the code holds today, and say
   in your report that it exists and is not committed; the supervisor copies it to the main checkout); `project.yml`
   points the app's targets at the tracked file (read XcodeGen's `configFiles`) and puts the setting in the
   Info.plist. With no address (CI, anyone else's clone) the app builds and the feedback row offers what it can
   without one (TestFlight's own feedback, or hides the mail route: the smallest honest thing; test both). In
   `scripts/release.sh`, one check before anything is archived: the address is set, or the release stops with one
   line saying which file to create. Prove it: `xcodegen generate`, a Mac Debug build with the local file (the
   built app's Info.plist holds the address) and one without it (it does not, and the app's tests pass).
3. **Replace the rest**: home paths become `~/…` or `<repo>/…`; the UDID becomes "the phone's id (`xcrun devicectl
   list devices`)"; a surname outside an identifier goes; a tester's name becomes "a friend" or "a tester". Keep
   every sentence true and readable. The documents' meaning does not change, and nothing else in them is edited.
4. **The licence, copyright lines, the app's About page, the Mac's menu, Info.plist strings**: what a person's name
   appears in there, list it; change only what is not shown to testers as the maker's name on purpose.
5. Afterwards the same greps come back empty except for what the list above says stays. Give the greps and their
   output in your report.

Proof: the greps; `xcodegen generate` leaves the project building; `HITListTests` whole on the Mac at the end
(`BetaFeedbackTests` pin the address today: they pin the new behaviour instead); `swift test` in `HITListCore` if you
touched it. Your report also says what the history still holds (count the commits whose author line or content
carry the address: `git log --all --format=%ae | sort | uniq -c`, `git log --all -S'<the address>' --oneline | wc
-l`), in numbers only, so George can decide what to do about the history.
