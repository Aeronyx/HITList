import Foundation
import OSLog
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A move between the engines is written as a preference and takes effect when the app next starts
/// (`SyncEngine.move`). Left to the person, that start can be weeks away: a Mac's app is rarely quit, and a phone's
/// stays in the background. Until then this device is on one sync while the person's other devices are on the
/// other, and they do not see each other's changes (`dev/SYNC-ENGINE.md` section 11). So the app sees to that start
/// itself, at the first moment nobody is looking (round 34):
///
/// - **iPhone and iPad**: once the app is in the background with a move waiting, what is unsaved is saved and the
///   process ends. To the person it is what the system does to a background app every day: the next opening is a
///   fresh start, on the other engine. Only a process the person has had in front of them: one the system started
///   in the background (a widget's button, a push, a refresh) is doing that work and is left to it.
/// - **Mac**: when HITList is not the active app, it relaunches itself behind the other apps, as the hand move
///   relaunches it (the new instance waits for this one to exit before it opens the store).
///
/// Never while something a person may be typing in is open: a card (`PopoutController.isAnyCardOpen`), or any sheet,
/// alert or panel (`isSomethingPresented`: the filter, Group and label editors, Review Inbox, the profile, an
/// invitation, an import or export). Never under tests, never when a Debug argument chose the engine (nothing waits then), never for a side store on
/// the Mac that its launcher named (a relaunch through the system would not reopen it), and nothing at all when no
/// move waits.
@MainActor
enum SyncEngineMoveFinish {
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")
    private static var installed = false
    private static var container: ModelContainer?
    /// The tests' way to see what would have been done without ending or relaunching the process.
    static var finishForTesting: (@MainActor () -> Void)?

    /// Whether a move waits for the next launch: the store's preference names the other engine and no argument
    /// chose this launch's.
    static func isWaiting(storeName: String = ModelContainerFactory.storeName, defaults: UserDefaults = AppGroup.defaults,
                          current: SyncEngineBoard.Engine = SyncEngineSwitch.current,
                          byArgument: Bool = SyncEngineSwitch.launchedByArgument) -> Bool {
        !byArgument && SyncEngineSwitch.nextEngine(storeName: storeName, defaults: defaults) != current
    }

    /// Written just before the app ends or relaunches itself: the engine that start was meant to open on.
    static func triedKey(_ store: String) -> String { "syncEngine.moveFinish.tried.\(store)" }

    /// A start that was made for a move and still finds that move waiting does not make another: whatever keeps the
    /// store from opening on the other engine, ending the app again and again would not mend it.
    static func givesUp(waiting: Bool, triedFor: String?, next: SyncEngineBoard.Engine) -> Bool {
        waiting && triedFor == next.rawValue
    }

    private static var gaveUp = false
    /// iPhone and iPad: this process has been in front of the person at least once.
    private static var wasActive = false

    /// Whether a relaunch through the system opens this store again: the real store, and a Development build's own
    /// (`SyncStoreGuard` names it again at every launch). Any other side store is named by its launcher's
    /// environment, which a relaunch drops.
    static func reopensByItself(storeName: String) -> Bool {
        storeName == ModelContainerFactory.mainStoreName
            || storeName == ModelContainerFactory.storeName(suffix: SyncStoreGuard.developmentSuffix)
    }

    /// Whether this moment is one the app may end or relaunch itself in (pure, for the tests).
    static func mayFinish(waiting: Bool, inMemory: Bool, quiet: Bool, cardOpen: Bool, presented: Bool = false,
                          wasActive: Bool = true) -> Bool {
        waiting && !inMemory && quiet && !cardOpen && !presented && wasActive
    }

    /// Whether a sheet, an alert or a panel is open over any of the app's windows: something a person may be in the
    /// middle of, which a card is not the only kind of (brief 172's finding 7).
    static var isSomethingPresented: Bool {
        #if os(macOS)
        return NSApplication.shared.modalWindow != nil
            || NSApplication.shared.windows.contains { $0.attachedSheet != nil || $0.sheets.isEmpty == false }
        #else
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
        #endif
    }

    /// From `HITListApp.init`. Arms two observers and nothing else; they do nothing while no move waits.
    static func install(container: ModelContainer,
                        isTesting: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil) {
        guard !installed, !isTesting else { return }
        installed = true
        self.container = container
        let store = ModelContainerFactory.storeName
        let tried = AppGroup.defaults.string(forKey: triedKey(store))
        if givesUp(waiting: isWaiting(), triedFor: tried, next: SyncEngineSwitch.nextEngine()) {
            gaveUp = true
            CloudSyncMonitor.shared.write(.note, "The move was finished once and still waits: HITList leaves it for a later start")
        } else if !isWaiting(), tried != nil {
            AppGroup.defaults.removeObject(forKey: triedKey(store))
        }
        #if os(macOS)
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { finishIfQuiet() }
        }
        #else
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { wasActive = true }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { finishIfQuiet() }
        }
        #endif
    }

    /// The move was just written (`SyncEngineAutoMove`, or the hand move on a phone): if this is already a quiet
    /// moment (a Mac in the background), finish now; otherwise the observers will.
    static func moveWritten() {
        finishIfQuiet()
    }

    static func finishIfQuiet() {
        // Never under tests (nothing was installed), unless a test asks to see what would be done.
        guard installed || finishForTesting != nil else { return }
        guard !gaveUp else { return }
        let waiting = isWaiting()
        guard waiting else { return }
        #if os(macOS)
        // A relaunch already under way (the hand move's own) is the finish: never a second instance.
        guard !SyncEngine.isRelaunching else { return }
        let quiet = !NSApplication.shared.isActive
        let active = true
        guard reopensByItself(storeName: ModelContainerFactory.storeName) else { return }
        #else
        let quiet = UIApplication.shared.applicationState == .background
        let active = wasActive || UIApplication.shared.applicationState == .active
        #endif
        #if DEBUG
        if ModelContainerFactory.storeName != ModelContainerFactory.mainStoreName {
            // A rehearsal reads why a waiting move was or was not finished at this moment.
            print("REHEARSAL finish: quiet \(quiet), card open \(PopoutController.isAnyCardOpen), "
                  + "presented \(isSomethingPresented), was in front \(active)")
            fflush(stdout)
        }
        #endif
        guard mayFinish(waiting: waiting, inMemory: ModelContainerFactory.isRunningInMemory, quiet: quiet,
                        cardOpen: PopoutController.isAnyCardOpen, presented: isSomethingPresented,
                        wasActive: active) else { return }
        if let finishForTesting { finishForTesting(); return }
        finish()
    }

    private static func finish() {
        let target = SyncEngineSwitch.nextEngine()
        // What is unsaved is saved before the process goes (just before, below: the engine's stop and the wait come
        // between): the next start reads the store, not this process.
        let save: @MainActor () -> Void = {
            if let context = container?.mainContext, context.hasChanges { try? context.save() }
        }
        save()
        CloudSyncMonitor.shared.write(.note, "Finishing the move to \(target == .own ? "the new sync" : "the earlier sync"): HITList starts again by itself")
        #if DEBUG
        print("REHEARSAL finish: ending or relaunching for the move to \(target.rawValue)")
        fflush(stdout)
        #endif
        #if os(macOS)
        Task { @MainActor in
            // The running engine stops before the process goes, so the transport's state is written.
            if let running = SyncEngine.shared { await running.stop() }
            save()
            AppGroup.defaults.set(target.rawValue, forKey: triedKey(ModelContainerFactory.storeName))
            SyncEngine.relaunchMac(defaults: AppGroup.defaults, activates: false)
        }
        #else
        // Held open for the moment the save and the log line need, then the process ends: the system would have
        // ended it sooner or later, and the next opening is the one the move waits for.
        let app = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        task = app.beginBackgroundTask { app.endBackgroundTask(task) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard app.applicationState == .background, isWaiting(), !PopoutController.isAnyCardOpen, !isSomethingPresented else {
                // The person came straight back: not now. The next time it goes to the background.
                app.endBackgroundTask(task)
                return
            }
            // As on the Mac: the running engine stops first, so the transport's state is written.
            if let running = SyncEngine.shared { await running.stop() }
            save()
            log.notice("move: ending the process in the background so the next opening is on \(target.rawValue, privacy: .public)")
            AppGroup.defaults.set(target.rawValue, forKey: triedKey(ModelContainerFactory.storeName))
            exit(0)
        }
        #endif
    }
}
