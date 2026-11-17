# 152: what can crash or hang the app (read-only review)

Before a real launch. A friend's two crash reports in round 29 were one cause: an `async`
`UNUserNotificationCenterDelegate` method, which makes the system's completion handler run off the main thread
inside UIKit (`dev/briefs/ROUND-29.md`). Find the rest of that family and its cousins, in the app, the widget
extension, the share extension and the MCP helper. (Do not read `crashreports/`: it holds testers' names.)

1. **Delegates and callbacks the system calls**: every `async` implementation of an Objective-C delegate method with
   a completion handler (UserNotifications, UIKit and AppKit application and scene delegates, CloudKit share
   acceptance, Core Location, Core Spotlight, EventKit, background tasks, App Intents), every `@MainActor` type
   handed to an API that calls back on another queue, every `nonisolated(unsafe)` and `@unchecked Sendable` (say for
   each whether what it claims is true), every `DispatchQueue.main.sync`, every continuation that could be resumed
   twice or never.
2. **Traps**: `fatalError`, `preconditionFailure`, `try!`, `as!`, force unwraps, unchecked array indexing and
   `first!`/`last!`, integer overflow, `Dictionary(uniqueKeysWithValues:)` on keys a store could hold twice (two
   rows with one `id` exist in the wild: `Deduplicator`), ranges built from dates or counts that can run backwards,
   division by a count that can be zero. Only those a real store, a real clock or a real person can reach; say how.
3. **SwiftData**: a model object touched after its row was deleted (by the person in another window, by a merge, by
   sync arriving) is a crash in SwiftData: every view, popout, timer or task that holds a model across an `await`
   or across a sheet's lifetime; `@Query` results indexed after a delete; a `PersistentIdentifier` looked up in the
   wrong context; models passed between actors.
4. **Hangs and the watchdog**: work on the main thread at launch (the system kills an app that takes too long to
   launch: what does `HITListApp.init` do before the first frame, with 5,000 tasks?), in `applicationWillTerminate`
   and `scenePhase` changes, `Thread.sleep` and semaphores on the main thread, a synchronous file or network call
   there, an unbounded loop over every task in a view's body.
5. **Background**: `BGTaskScheduler` (never `submit` in `App.init`: it hung a launch once), the silent-push handler's
   time limit and its completion called exactly once, the widget's intents (on iOS they launch the app cold), the
   background refresh's expiration handler.
6. **Timers and animation**: every `Timer`, `Task.sleep` loop and `TimelineView` schedule: does each end, and is any
   running while nothing is on screen (the rule since round 26: no timer with nothing pending, nothing endless in
   the Mac's toolbar)?
7. **Memory**: images (the avatar, companions' sprites), caches without a bound, a `NotificationCenter` observer or
   a task that keeps its owner alive for good.
8. **The extensions' limits**: a widget or share extension that opens the whole store or fetches every task within
   the extension's memory ceiling.

Write `FINDINGS.md` in your notes folder, and report as the Round 32 block of `dev/briefs/COMMON.md` says.
