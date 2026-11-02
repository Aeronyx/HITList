import Foundation
import OSLog
#if os(macOS)
import AppKit
#endif

/// Settings → iCloud Sync → "Reset local cache and re-download…". Only sets a flag: the store can't be
/// moved while this process has it open, so `ModelContainerFactory.make()` moves it on the next launch.
enum LocalCacheReset {
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "storage")

    /// Only offered while iCloud has the data: without a signed-in account the local store is the only copy.
    @MainActor
    static var isAvailable: Bool {
        ModelContainerFactory.isCloudKitEnabled && CloudSyncMonitor.shared.accountStatus == .available
    }

    /// Asks for a reset of the store this launch opened (`storeName`), by name: another build on the
    /// device that opens a different store (TestFlight's HITList.store, a Development build's own) leaves
    /// the request alone, so a reset never lands on the wrong store.
    static func request(storeName: String = ModelContainerFactory.storeName, defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(storeName, forKey: ModelContainerFactory.resetLocalStoreKey)
        log.notice("Reset local store requested for \(storeName, privacy: .public); it runs on the next launch that opens it")
    }

    #if os(macOS)
    /// Relaunch approach: open a second instance of this bundle, and quit as soon as it is running.
    /// The new instance waits in `ModelContainerFactory.make()` until this one has exited before it
    /// moves the store. Quitting can't wait for `openApplication`'s completion: that fires only once
    /// the new instance has finished launching, which it doesn't while it waits for this one.
    /// Calls `failed` when no new instance appears within 10 s, so the caller can ask the user to quit
    /// and reopen instead (the flag stays set, so that finishes the reset too).
    @MainActor
    static func relaunch(failed: @escaping @MainActor () -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error { log.error("Relaunch failed: \(error.localizedDescription, privacy: .public)") }
        }
        let me = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        Task { @MainActor in
            for _ in 0..<100 {
                try? await Task.sleep(for: .milliseconds(100))
                let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                if others.contains(where: { $0.processIdentifier != me && !$0.isTerminated }) {
                    log.notice("Relaunched for reset; quitting this instance")
                    NSApplication.shared.terminate(nil)
                    return
                }
            }
            log.error("Relaunch for reset: no new instance appeared")
            failed()
        }
    }
    #endif
}
