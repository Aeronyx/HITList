# 154: where the app is slow with a large list, measured (review; builds and runs in a worktree of its own, changes no code)

Before a real launch. A friend who imports years of Todoist arrives with thousands of tasks on day one; George's
own store grows every day. Nothing has been measured at that size except the engine's first sync (round 31).
**Measure, then read**: a finding here is a number and the line that causes it, not a suspicion.

You have a worktree of your own so that you can build; **commit nothing and change no source file**.

How:

1. Build the Debug Mac app (`xcodebuild build -project HITList.xcodeproj -scheme HITList -configuration Debug
   -destination 'platform=macOS' -allowProvisioningUpdates -derivedDataPath build.noindex/154`,
   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).
2. A store of 5,000 tasks: launch once with `HITLIST_STORE_SUFFIX=p154` and `-seedSyncLoad 5000 -disableCloudKit YES
   -ApplePersistenceIgnoreState YES` (`open -g -n --env HITLIST_STORE_SUFFIX=p154 --stdout <file> <app> --args …`;
   read `seedSyncLoadIfRequested` in `HITList/Services/TaskActions.swift` for what it makes; if the load is too
   uniform to be a fair list, say so and say what a fair one needs). Always a side store, always
   `-disableCloudKit YES`; never `/Applications/HITList.app`; quit every app you start.
3. Measure with what the Mac has: launch to first frame (`HITList/Services/Sync/LaunchTiming.swift` and the log:
   `/usr/bin/log show --info --last 2m --predicate 'subsystem == "com.trammells.hitlist"'`), `sample <pid> 5` while
   you drive it with `scripts/window-drive.sh` (select a list, type in search, open a task, check one off, scroll),
   `ps -o %cpu,rss` at rest and while idle for a minute (the rule since round 26: 0.0% at rest between a
   companion's moves), memory after a walk through every list. A Debug build is slower than a release build
   everywhere; what matters is what grows with the number of tasks, so measure the same thing at 26 tasks
   (`-seedSampleData`) and at 5,000 and report the ratio.
4. Then read the code the samples point at. Usual causes in a SwiftData and SwiftUI app: a `@Query` of every task
   in a view that needs ten; filtering and sorting every task in a `body`; a fetch per row; work per keystroke
   without a debounce; `updatedAt` writes that invalidate every row; a widget snapshot or a Spotlight index rebuilt
   whole on every save; reminders rescheduled for every task on every save; the name merge after every import.

Report: a table of what you measured (the action, 26 tasks, 5,000 tasks, the ratio), then findings in the round's
format: the cause's `path:line`, the fix you would make, what it would save. Leave out anything under 100 ms at
5,000 tasks unless it runs on every keystroke or every frame. Write `FINDINGS.md` in your notes folder, and report
as the Round 32 block of `dev/briefs/COMMON.md` says.
