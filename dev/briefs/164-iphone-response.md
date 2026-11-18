# 164: the iPhone answers a tap at once: measured on George's phone, fixed, measured again (code)

George, 2026-11-18, on TestFlight 0.9.13 with about sixty tasks: "The mobile app is also a bit slow to respond now
(taps take 1 second or so to register, some pages are slow to load/transfer between, etc.)." Sixty tasks is not a
long list: this is not the 5,000-task work of round 32 (brief 158, which is on master and which he has not had on
his phone as a released build). He has offered the phone: "I'll connect my iPhone again in a few minutes so you can
do real mobile testing as well."

**You alone use the phone** (an iPhone 16; its id from `xcrun devicectl list devices`, written `<UDID>` below). Rules, none to be bent: never delete the
app on it; never open the real store (a Development-signed build opens `HITList-Development.store` by itself, and
every launch of yours passes `HITLIST_STORE_SUFFIX=r164` as well); `-disableCloudKit YES` on every launch (nothing
of yours talks to iCloud); never answer a system dialog on it; if it is locked or asks for trust, do not wait for
it: work on your simulator and say so. Installing your build replaces his TestFlight app (his data stays; he
reinstalls from TestFlight afterwards): say in your report that it is installed. Build and install:
`xcodebuild build -project HITList.xcodeproj -scheme HITList -configuration Debug -destination
'id=<UDID>' -derivedDataPath build.noindex/164 -allowProvisioningUpdates`, `xcrun devicectl
device install app --device <UDID> build.noindex/164/Build/Products/Debug-iphoneos/HITList.app`, `xcrun devicectl
device process launch --device <UDID> --terminate-existing --console --environment-variables
'{"HITLIST_STORE_SUFFIX":"r164"}' com.trammells.hitlist -- -disableCloudKit YES -seedDemoData YES`. A Debug build is
slower than his: judge by where the time goes and by before and after, and build Release for the same device once
(`-configuration Release`, same suffix) to see the numbers he would.

**Yours**: whatever the measurements name, in `HITList/Views` and `HITList/Services`, **except**: `Views/Upcoming/`
(agent 161), `Views/Popouts/QuickAddPopout.swift`, `CompactQuickAddCard.swift` and `Views/Tips/` (162),
`Views/Settings/` and `SettingsView.swift` (163), `Services/SyncEngine/` and core's `Sync/` (165, 167),
`Views/Account/BetaFeedback.swift`, `project.yml`, `scripts/` (166). A cause inside one of those: write the fix as a
diff in your notes folder and name it in your report. No model or schema change.

1. **Measure before guessing.** The actions a person makes all day, each timed from the touch to the first frame
   that answers it, on the phone (and on your simulator for comparison): switching each tab; opening and closing
   quick add; adding a task; checking one off; opening a task's card and closing it; opening Browse, a Group, a
   label; opening Settings and one page; pulling Today down. Use what gives a number and a place: an XCUITest that
   performs each action with `measure` on the device, signposts, `xctrace record --template 'Time Profiler'`
   (`--device`, `--attach HITList`) while the test taps, the main thread's stalls. Round 32's tools for the Mac are
   in the notes folder (`round-32/154-performance-review/`, `158-performance-fixes/`); reuse what fits.
2. **Two different faults look alike; tell them apart.** (a) *The tap is recognised late*: a gesture waiting on
   another (a double tap, a long press, a drag, a swipe action or a context menu on the same view), a control under
   an overlay or a glass container that takes the touch first, a button inside a scroll view with delayed touches.
   The main thread is idle during the wait. (b) *The tap is recognised at once and the answer is slow*: work on the
   main thread on every save or every appearance (rescheduling all notifications, rebuilding widget snapshots,
   backups, counts, Spotlight, the sync monitor's comparison, a fetch in a view's `init` or `body`, a list rebuilt
   when a popout opens, a companion's or weather's `TimelineView` redrawing a whole screen, layout of the glass
   effects). Name which each slow action is, with the evidence.
3. **Fix what the numbers name, worst first**, each with its number before and after on the phone. The target: a
   tap's first answering frame within 100 ms, a tab or a card open within 250 ms, on a Release build with the demo
   week. A fix moves work off the main thread, makes it once instead of per save, or removes a gesture's wait; it
   never changes what a screen shows, what a save stores, or when a reminder fires. Each fix has a test where a
   test can reach it (the work does not run when it has nothing to do; the gesture's action fires).
4. **What you find and do not fix** goes in the report with its number and place: the supervisor decides.

Proof: the table of actions, before and after, Debug and Release, phone and simulator; `HITListTests` whole on the
Mac and on your simulator at the end (`SIMULATOR=HITList-164 scripts/test.sh ios`); `HITListUITests`,
`SweepPolishUITests`, `EditorSafetyUITests` on your simulator. Your perf test file stays in the repository only if
it runs on demand (skipped unless an environment variable asks for it), as round 32's did.
